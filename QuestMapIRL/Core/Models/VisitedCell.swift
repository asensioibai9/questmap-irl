import Foundation
import SwiftData

/// Celda de niebla revelada. La clave viene de FogGrid.key(for:).
@Model
final class VisitedCell {
    @Attribute(.unique) var key: String
    var firstVisit: Date

    init(key: String, firstVisit: Date = .now) {
        self.key = key
        self.firstVisit = firstVisit
    }
}
