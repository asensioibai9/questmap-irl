import Foundation

/// Resumen de estadísticas calculado a partir de los viajes y celdas guardados.
struct TravelStats: Equatable {
    var kilometers: Double = 0
    var routesCompleted: Int = 0
    var uniqueDestinations: Int = 0
    var revealedCells: Int = 0
    var minutesNavigating: Int = 0
    var streakDays: Int = 0

    static func make(trips: [TripSnapshot], revealedCells: Int, calendar: Calendar = .current) -> TravelStats {
        let days = Set(trips.map { calendar.startOfDay(for: $0.date) })
        return TravelStats(
            kilometers: trips.reduce(0) { $0 + $1.distanceMeters } / 1000,
            routesCompleted: trips.count,
            uniqueDestinations: Set(trips.map(\.destinationKey)).count,
            revealedCells: revealedCells,
            minutesNavigating: Int(trips.reduce(0) { $0 + $1.durationSeconds } / 60),
            streakDays: streak(in: days, calendar: calendar)
        )
    }

    /// Días consecutivos que terminan hoy (o ayer) con actividad.
    private static func streak(in days: Set<Date>, calendar: Calendar) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// Copia plana de un viaje, para no depender de SwiftData en el dominio.
struct TripSnapshot {
    let date: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let destinationKey: String
}

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let xp: Int
    let isUnlocked: (TravelStats) -> Bool
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "km100", title: "Cien kilómetros",
                    detail: "Recorre 100 km en total.", xp: 150) { $0.kilometers >= 100 },
        Achievement(id: "zonas50", title: "Cartógrafo novato",
                    detail: "Revela 50 zonas con la niebla.", xp: 100) { $0.revealedCells >= 50 },
        Achievement(id: "destinos5", title: "Cinco lugares nuevos",
                    detail: "Visita 5 destinos distintos.", xp: 100) { $0.uniqueDestinations >= 5 },
        Achievement(id: "rutas20", title: "Veinte misiones",
                    detail: "Completa 20 rutas.", xp: 200) { $0.routesCompleted >= 20 },
        Achievement(id: "racha7", title: "Semana de viaje",
                    detail: "Usa la app 7 días seguidos.", xp: 150) { $0.streakDays >= 7 }
    ]

    static func unlocked(for stats: TravelStats) -> [Achievement] {
        all.filter { $0.isUnlocked(stats) }
    }

    /// Nivel cosmético: no afecta a la navegación.
    static func level(forXP xp: Int) -> Int { xp / 500 + 1 }

    static func experience(for stats: TravelStats) -> Int {
        let fromAchievements = unlocked(for: stats).reduce(0) { $0 + $1.xp }
        return fromAchievements + stats.routesCompleted * 20 + Int(stats.kilometers)
    }
}
