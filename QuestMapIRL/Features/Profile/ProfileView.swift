import SwiftUI
import SwiftData

/// Perfil: nivel cosmético, estadísticas, niebla revelada y logros.
struct ProfileView: View {
    @Environment(\.mapTheme) private var theme
    @Query(sort: \TripRecord.startedAt, order: .reverse) private var trips: [TripRecord]
    @Query private var cells: [VisitedCell]

    private var stats: TravelStats {
        TravelStats.make(
            trips: trips.map {
                TripSnapshot(date: $0.startedAt, distanceMeters: $0.distanceMeters,
                             durationSeconds: $0.durationSeconds, destinationKey: $0.destinationKey)
            },
            revealedCells: cells.count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    levelCard
                    statsGrid
                    achievements
                    if !trips.isEmpty { recentTrips }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Explorador")
        }
    }

    private var levelCard: some View {
        let xp = Achievements.experience(for: stats)
        let level = Achievements.level(forXP: xp)
        return VStack(spacing: 8) {
            Text("Nivel \(level)")
                .font(.system(.largeTitle, design: theme.titleDesign).weight(.heavy))
                .foregroundStyle(theme.accent)
            ProgressView(value: Double(xp % 500), total: 500).tint(theme.accent)
            Text("\(xp % 500) / 500 XP · nivel cosmético, sin ventajas en navegación")
                .font(.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(theme.panel, in: .rect(cornerRadius: 20))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Kilómetros", String(format: "%.0f", stats.kilometers))
            stat("Rutas", "\(stats.routesCompleted)")
            stat("Lugares", "\(stats.uniqueDestinations)")
            stat("Zonas reveladas", "\(stats.revealedCells)")
            stat("Minutos", "\(stats.minutesNavigating)")
            stat("Racha", "\(stats.streakDays) días")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: theme.titleDesign).weight(.bold))
            Text(title).font(.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(theme.panel, in: .rect(cornerRadius: 16))
        .foregroundStyle(theme.textPrimary)
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logros").font(.headline).foregroundStyle(theme.textPrimary)
            ForEach(Achievements.all) { achievement in
                let unlocked = achievement.isUnlocked(stats)
                HStack {
                    Image(systemName: unlocked ? "rosette" : "lock.fill")
                        .foregroundStyle(unlocked ? theme.accent : theme.textSecondary)
                    VStack(alignment: .leading) {
                        Text(achievement.title).font(.subheadline.weight(.semibold))
                        Text(achievement.detail).font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Text("+\(achievement.xp) XP").font(.caption.monospacedDigit())
                }
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.panel.opacity(unlocked ? 1 : 0.6), in: .rect(cornerRadius: 14))
            }
        }
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Últimas rutas").font(.headline).foregroundStyle(theme.textPrimary)
            ForEach(trips.prefix(5)) { trip in
                HStack {
                    VStack(alignment: .leading) {
                        Text(trip.destinationName).font(.subheadline.weight(.semibold))
                        Text(trip.startedAt, style: .date).font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f km", trip.distanceMeters / 1000)).font(.caption.monospacedDigit())
                }
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.panel, in: .rect(cornerRadius: 14))
            }
        }
    }
}
