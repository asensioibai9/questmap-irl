import Foundation
@testable import QuestMapIRL

/// Sustituye la red: cada petición la contesta `responder`. Las pruebas son secuenciales, así que
/// el estado estático es suficiente.
final class StubURLProtocol: URLProtocol {
    typealias Outcome = Result<(status: Int, headers: [String: String], body: Data), Error>

    private static let lock = NSLock()
    private static var _responder: ((URLRequest) -> Outcome)?
    private static var _requests: [URLRequest] = []

    static var responder: ((URLRequest) -> Outcome)? {
        get { lock.lock(); defer { lock.unlock() }; return _responder }
        set { lock.lock(); _responder = newValue; lock.unlock() }
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); _responder = nil; _requests = []; lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let responder = Self._responder
        Self.lock.unlock()

        switch responder?(request) ?? .failure(URLError(.badServerResponse)) {
        case .success(let reply):
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func ok(_ body: Data, headers: [String: String] = [:]) -> StubURLProtocol.Outcome {
    .success((200, headers, body))
}

func http(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> StubURLProtocol.Outcome {
    .success((status, headers, Data(body.utf8)))
}

/// Reintentos sin esperas reales.
func instantRetry(maxRetries: Int = 2) -> RetryPolicy {
    RetryPolicy(maxRetries: maxRetries, baseDelay: 0.001, maxRetryAfter: 4, sleep: { _ in })
}

// MARK: - Codificador mínimo de tiles vectoriales (para fixtures)

struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 { bytes.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        bytes.append(UInt8(v))
    }

    mutating func key(_ field: Int, _ wire: Int) { varint(UInt64(field << 3 | wire)) }

    mutating func message(_ field: Int, _ inner: ProtoWriter) { raw(field, inner.bytes) }

    mutating func raw(_ field: Int, _ data: [UInt8]) {
        key(field, 2); varint(UInt64(data.count)); bytes += data
    }

    mutating func string(_ field: Int, _ text: String) { raw(field, Array(text.utf8)) }

    mutating func number(_ field: Int, _ value: UInt64) { key(field, 0); varint(value) }
}

struct FixturePOI {
    var poiClass: String
    var subclass: String?
    var name: String?
    /// Posición dentro del tile, en unidades de `extent` (0...4096).
    var x: Int
    var y: Int
    var geometryType = 1
}

/// Construye un tile con una capa `poi` (y una capa `water` que debe ignorarse).
func makeFixtureTile(pois: [FixturePOI], extent: Int = 4096) -> Data {
    var keys: [String] = []
    var values: [String] = []
    func keyIndex(_ k: String) -> Int { if let i = keys.firstIndex(of: k) { return i }; keys.append(k); return keys.count - 1 }
    func valueIndex(_ v: String) -> Int { if let i = values.firstIndex(of: v) { return i }; values.append(v); return values.count - 1 }
    func zigzag(_ n: Int) -> UInt64 { UInt64(bitPattern: Int64((n << 1) ^ (n >> 63))) }

    var layer = ProtoWriter()
    layer.string(1, "poi")
    for poi in pois {
        var tags: [UInt64] = [UInt64(keyIndex("class")), UInt64(valueIndex(poi.poiClass))]
        if let subclass = poi.subclass { tags += [UInt64(keyIndex("subclass")), UInt64(valueIndex(subclass))] }
        if let name = poi.name { tags += [UInt64(keyIndex("name")), UInt64(valueIndex(name))] }
        var tagBytes = ProtoWriter(); tags.forEach { tagBytes.varint($0) }
        var geometry = ProtoWriter()
        geometry.varint((1 << 3) | 1); geometry.varint(zigzag(poi.x)); geometry.varint(zigzag(poi.y))
        var feature = ProtoWriter()
        feature.raw(2, tagBytes.bytes)
        feature.number(3, UInt64(poi.geometryType))
        feature.raw(4, geometry.bytes)
        layer.message(2, feature)
    }
    for key in keys { layer.string(3, key) }
    for value in values { var v = ProtoWriter(); v.string(1, value); layer.message(4, v) }
    layer.number(5, UInt64(extent))

    var water = ProtoWriter()
    water.string(1, "water")
    water.number(5, 4096)

    var tile = ProtoWriter()
    tile.message(3, water)
    tile.message(3, layer)
    return Data(tile.bytes)
}

func tileJSONData(maxZoom: Int = 14, template: String = "https://tiles.test/planet/v1/{z}/{x}/{y}.pbf") -> Data {
    Data("{\"tiles\":[\"\(template)\"],\"maxzoom\":\(maxZoom)}".utf8)
}
