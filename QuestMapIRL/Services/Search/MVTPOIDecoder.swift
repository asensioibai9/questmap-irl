import Foundation

/// Punto de interés leído de la capa `poi` de un tile vectorial.
struct TilePOI: Equatable {
    let name: String?
    let poiClass: String
    let subclass: String?
    let latitude: Double
    let longitude: Double
}

/// Decodificador mínimo de tiles vectoriales (Mapbox Vector Tile, protobuf) que solo extrae los
/// puntos de la capa `poi`. Sin dependencias externas.
enum MVTPOIDecoder {
    enum DecodeError: Error { case malformed }

    static func decode(_ data: Data, z: Int, x: Int, y: Int) throws -> [TilePOI] {
        let bytes = [UInt8](data)
        var top = ProtoReader(bytes)
        var result: [TilePOI] = []
        while let (field, wire) = try top.nextField() {
            if field == 3, wire == 2 {
                let layer = try top.lengthDelimited()
                result += try decodeLayer(layer, z: z, x: x, y: y)
            } else {
                try top.skip(wire)
            }
        }
        return result
    }

    // MARK: Capa

    private static func decodeLayer(_ bytes: ArraySlice<UInt8>, z: Int, x: Int, y: Int) throws -> [TilePOI] {
        var scan = ProtoReader(bytes)
        var name: String?
        while let (field, wire) = try scan.nextField() {
            if field == 1, wire == 2 { name = String(decoding: try scan.lengthDelimited(), as: UTF8.self); break }
            try scan.skip(wire)
        }
        guard name == "poi" else { return [] }

        var keys: [String] = []
        var values: [String?] = []
        var features: [ArraySlice<UInt8>] = []
        var extent = 4096
        var reader = ProtoReader(bytes)
        while let (field, wire) = try reader.nextField() {
            switch (field, wire) {
            case (2, 2): features.append(try reader.lengthDelimited())
            case (3, 2): keys.append(String(decoding: try reader.lengthDelimited(), as: UTF8.self))
            case (4, 2): values.append(try decodeStringValue(try reader.lengthDelimited()))
            case (5, 0): extent = Int(try reader.varint())
            default: try reader.skip(wire)
            }
        }
        guard extent > 0 else { throw DecodeError.malformed }

        let classKey = keys.firstIndex(of: "class")
        let subclassKey = keys.firstIndex(of: "subclass")
        let nameKey = keys.firstIndex(of: "name")
        let nameEsKey = keys.firstIndex(of: "name:es")
        guard let classKey else { return [] }

        var points: [TilePOI] = []
        for feature in features {
            var reader = ProtoReader(feature)
            var tags: [Int] = []
            var geometry: [UInt32] = []
            var type = 0
            while let (field, wire) = try reader.nextField() {
                switch (field, wire) {
                case (2, 2):
                    var packed = ProtoReader(try reader.lengthDelimited())
                    while !packed.atEnd { tags.append(Int(try packed.varint())) }
                case (3, 0): type = Int(try reader.varint())
                case (4, 2):
                    var packed = ProtoReader(try reader.lengthDelimited())
                    while !packed.atEnd { geometry.append(UInt32(truncatingIfNeeded: try packed.varint())) }
                default: try reader.skip(wire)
                }
            }
            guard type == 1 else { continue }          // solo puntos

            func value(for key: Int?) -> String? {
                guard let key else { return nil }
                var i = 0
                while i + 1 < tags.count {
                    if tags[i] == key, tags[i + 1] < values.count { return values[tags[i + 1]] }
                    i += 2
                }
                return nil
            }
            guard let poiClass = value(for: classKey) else { continue }
            let label = value(for: nameEsKey) ?? value(for: nameKey)
            let subclass = value(for: subclassKey)

            for (px, py) in pointPositions(from: geometry) {
                let n = pow(2.0, Double(z))
                let lon = (Double(x) + Double(px) / Double(extent)) / n * 360 - 180
                let merc = Double.pi * (1 - 2 * (Double(y) + Double(py) / Double(extent)) / n)
                let lat = atan(sinh(merc)) * 180 / .pi
                points.append(TilePOI(name: label, poiClass: poiClass, subclass: subclass, latitude: lat, longitude: lon))
            }
        }
        return points
    }

    /// Geometría de puntos: `MoveTo` (comando 1) seguido de pares (dx, dy) en zigzag, acumulados.
    private static func pointPositions(from geometry: [UInt32]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var i = 0, x = 0, y = 0
        while i < geometry.count {
            let command = geometry[i] & 7
            let count = Int(geometry[i] >> 3)
            i += 1
            guard command == 1 else { break }
            for _ in 0..<count {
                guard i + 1 < geometry.count else { return result }
                x += zigzag(geometry[i]); y += zigzag(geometry[i + 1])
                result.append((x, y))
                i += 2
            }
        }
        return result
    }

    private static func zigzag(_ n: UInt32) -> Int { Int(n >> 1) ^ -Int(n & 1) }

    /// Valor de propiedad: solo interesan las cadenas (campo 1).
    private static func decodeStringValue(_ bytes: ArraySlice<UInt8>) throws -> String? {
        var reader = ProtoReader(bytes)
        var text: String?
        while let (field, wire) = try reader.nextField() {
            if field == 1, wire == 2 { text = String(decoding: try reader.lengthDelimited(), as: UTF8.self) } else { try reader.skip(wire) }
        }
        return text
    }
}

/// Lector de protobuf (solo lo necesario para MVT).
struct ProtoReader {
    private let bytes: ArraySlice<UInt8>
    private var index: Int

    init(_ bytes: [UInt8]) { self.bytes = bytes[...]; index = bytes.startIndex }
    init(_ bytes: ArraySlice<UInt8>) { self.bytes = bytes; index = bytes.startIndex }

    var atEnd: Bool { index >= bytes.endIndex }

    mutating func varint() throws -> UInt64 {
        var shift: UInt64 = 0, result: UInt64 = 0
        while index < bytes.endIndex {
            let byte = bytes[index]; index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw MVTPOIDecoder.DecodeError.malformed }
        }
        throw MVTPOIDecoder.DecodeError.malformed
    }

    mutating func nextField() throws -> (field: Int, wire: Int)? {
        guard !atEnd else { return nil }
        let key = try varint()
        return (Int(key >> 3), Int(key & 7))
    }

    mutating func lengthDelimited() throws -> ArraySlice<UInt8> {
        let length = Int(try varint())
        guard length >= 0, index + length <= bytes.endIndex else { throw MVTPOIDecoder.DecodeError.malformed }
        defer { index += length }
        return bytes[index..<(index + length)]
    }

    mutating func skip(_ wire: Int) throws {
        switch wire {
        case 0: _ = try varint()
        case 1: index += 8
        case 2: _ = try lengthDelimited()
        case 5: index += 4
        default: throw MVTPOIDecoder.DecodeError.malformed
        }
        if index > bytes.endIndex { throw MVTPOIDecoder.DecodeError.malformed }
    }
}
