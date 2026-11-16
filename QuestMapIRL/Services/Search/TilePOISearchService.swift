import Foundation
import CoreLocation

/// Lugares cercanos por categoría leídos de los MISMOS tiles vectoriales que dibujan el mapa
/// (OpenFreeMap, capa `poi`). Son archivos estáticos servidos por CDN, así que no dependen de un
/// servidor de consultas saturado (Overpass, que en las pruebas devolvía 502 «at capacity»).
///
/// Los tiles son públicos y sin clave. Para publicar con muchos usuarios conviene un proveedor
/// contratado (ver MapProviderConfig).
struct TilePOISearchService: NearbySearchProviding, Sendable {
    var tileJSONURL = URL(string: MapProviderConfig.openFreeMap.tilesURL)!
    var client = ServiceClient(service: "tiles")
    var cache = TileCache.shared
    var maxResults = 40

    func nearby(_ category: PlaceCategory, around center: CLLocationCoordinate2D, radiusMeters: Int) async throws -> [Place] {
        guard CLLocationCoordinate2DIsValid(center), abs(center.latitude) < 85 else { throw SearchError.configuration }

        let template = try await tileTemplate()
        let z = min(14, template.maxZoom)
        let tiles = Self.tiles(around: center, radiusMeters: Double(radiusMeters), z: z)

        // El tile central es imprescindible; los vecinos mejoran el resultado pero pueden faltar.
        var pois: [TilePOI] = []
        var firstError: SearchError?
        try await withThrowingTaskGroup(of: (Bool, Result<[TilePOI], SearchError>).self) { group in
            for (index, tile) in tiles.enumerated() {
                group.addTask {
                    do { return (index == 0, .success(try await loadTile(tile, template: template.url))) }
                    catch let error as SearchError { return (index == 0, .failure(error)) }
                }
            }
            var centerFailed: SearchError?
            for try await (isCenter, outcome) in group {
                switch outcome {
                case .success(let list): pois += list
                case .failure(let error):
                    firstError = firstError ?? error
                    if isCenter { centerFailed = error }
                }
            }
            if let centerFailed, pois.isEmpty { throw centerFailed }
        }
        if pois.isEmpty, let firstError { throw firstError }

        return Self.places(from: pois, category: category, center: center,
                           radiusMeters: Double(radiusMeters), limit: maxResults)
    }

    // MARK: Plantilla de tiles (TileJSON)

    private func tileTemplate() async throws -> TileTemplate {
        if let cached = await cache.template() { return cached }
        var request = URLRequest(url: tileJSONURL)
        request.timeoutInterval = 10
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let data = try await client.data(for: request, operation: "tilejson")
            let template = try Self.parseTileJSON(data)
            await cache.store(template: template)
            return template
        } catch let error as SearchError {
            // Con una plantilla antigua (hasta 24 h) se puede seguir buscando.
            if let stale = await cache.template(allowStale: true) { return stale }
            throw error
        }
    }

    static func parseTileJSON(_ data: Data) throws -> TileTemplate {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiles = object["tiles"] as? [String], let url = tiles.first,
              url.contains("{z}"), url.contains("{x}"), url.contains("{y}") else { throw SearchError.decoding }
        return TileTemplate(url: url, maxZoom: object["maxzoom"] as? Int ?? 14)
    }

    // MARK: Tiles

    struct TileID: Hashable { let z: Int, x: Int, y: Int }

    private func loadTile(_ tile: TileID, template: String) async throws -> [TilePOI] {
        let key = "\(template)|\(tile.z)/\(tile.x)/\(tile.y)"
        if let hit = await cache.pois(for: key) { return hit }
        let urlString = template
            .replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))
        guard let url = URL(string: urlString) else { throw SearchError.configuration }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("QuestMapIRL/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let data = try await client.data(for: request, operation: "tile")
        let list: [TilePOI]
        do { list = try MVTPOIDecoder.decode(data, z: tile.z, x: tile.x, y: tile.y) }
        catch { throw SearchError.decoding }
        await cache.store(pois: list, for: key)
        return list
    }

    /// Tiles que cubren el círculo de búsqueda; el primero es el que contiene el centro.
    static func tiles(around center: CLLocationCoordinate2D, radiusMeters: Double, z: Int) -> [TileID] {
        let n = Double(1 << z)
        func tileX(_ lon: Double) -> Int { Int(floor((lon + 180) / 360 * n)) }
        func tileY(_ lat: Double) -> Int {
            let rad = lat * .pi / 180
            return Int(floor((1 - asinh(tan(rad)) / .pi) / 2 * n))
        }
        let cx = tileX(center.longitude), cy = tileY(center.latitude)
        func bounds(_ x: Int, _ y: Int) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            func lat(_ ty: Double) -> Double { atan(sinh(.pi * (1 - 2 * ty / n))) * 180 / .pi }
            return (lat(Double(y + 1)), lat(Double(y)), Double(x) / n * 360 - 180, Double(x + 1) / n * 360 - 180)
        }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var found: [(Double, TileID)] = []
        let span = max(1, Int(ceil(radiusMeters / 1500)))
        for dx in -span...span {
            for dy in -span...span {
                let x = cx + dx, y = cy + dy
                guard y >= 0, y < (1 << z) else { continue }
                let wrappedX = ((x % (1 << z)) + (1 << z)) % (1 << z)
                let b = bounds(x, y)
                let nearest = CLLocation(latitude: min(max(center.latitude, b.minLat), b.maxLat),
                                         longitude: min(max(center.longitude, b.minLon), b.maxLon))
                let distance = here.distance(from: nearest)
                if distance <= radiusMeters { found.append((distance, TileID(z: z, x: wrappedX, y: y))) }
            }
        }
        // El tile central primero (distancia 0), después por cercanía.
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    // MARK: Resultado

    static func places(from pois: [TilePOI], category: PlaceCategory, center: CLLocationCoordinate2D,
                       radiusMeters: Double, limit: Int) -> [Place] {
        let match = category.tileMatch
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var seen = Set<String>()
        var scored: [(Double, Place)] = []
        for poi in pois where match.matches(poiClass: poi.poiClass, subclass: poi.subclass) {
            let distance = here.distance(from: CLLocation(latitude: poi.latitude, longitude: poi.longitude))
            guard distance <= radiusMeters else { continue }
            // Los tiles repiten los elementos que caen en el margen de varios tiles.
            let key = "\(poi.name ?? "")|\(poi.poiClass)|\(String(format: "%.5f,%.5f", poi.latitude, poi.longitude))"
            guard seen.insert(key).inserted else { continue }
            let place = Place(id: "poi-\(String(format: "%.5f,%.5f", poi.latitude, poi.longitude))-\(poi.poiClass)",
                              name: poi.name ?? category.singular,
                              subtitle: poi.name == nil ? "Sin nombre en el mapa" : category.singular,
                              latitude: poi.latitude, longitude: poi.longitude)
            scored.append((distance, place))
        }
        return scored.sorted { $0.0 < $1.0 }.prefix(limit).map(\.1)
    }
}

struct TileTemplate: Equatable, Sendable {
    let url: String
    let maxZoom: Int
}

/// Caché en memoria: plantilla de tiles (1 h) y POIs ya decodificados por tile (al cambiar de
/// categoría no se vuelve a descargar ni decodificar).
actor TileCache {
    static let shared = TileCache()

    private var storedTemplate: (template: TileTemplate, date: Date)?
    private var byTile: [String: [TilePOI]] = [:]
    private var order: [String] = []
    private let capacity = 24

    func template(allowStale: Bool = false) -> TileTemplate? {
        guard let storedTemplate else { return nil }
        let age = Date().timeIntervalSince(storedTemplate.date)
        return age < (allowStale ? 86_400 : 3_600) ? storedTemplate.template : nil
    }

    func store(template: TileTemplate) { storedTemplate = (template, Date()) }

    func pois(for key: String) -> [TilePOI]? { byTile[key] }

    func store(pois list: [TilePOI], for key: String) {
        if byTile[key] == nil { order.append(key) }
        byTile[key] = list
        while order.count > capacity { byTile[order.removeFirst()] = nil }
    }

    func clear() { storedTemplate = nil; byTile = [:]; order = [] }
}
