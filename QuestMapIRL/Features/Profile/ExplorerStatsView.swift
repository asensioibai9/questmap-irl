import SwiftUI
import SwiftData

/// Estadísticas y logros: nivel cosmético, estadísticas, niebla revelada y logros. Todo gratuito.
struct ExplorerStatsView: View {
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
        ScrollView {
            if trips.isEmpty {
                ContentUnavailableView(
                    "Aún no has viajado",
                    systemImage: "map",
                    description: Text("Completa tu primera ruta y aquí verás kilómetros, zonas reveladas y logros.")
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: 16) {
                    levelCard
                    statsGrid
                    achievements
                    recentTrips
                }
                .padding(16)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Estadísticas y logros")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.mapTheme, ThemeCatalog.ciudadNocturna)
        .preferredColorScheme(.dark)
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
                .font(.caption).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: theme.cornerRadius + 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius + 6, style: .continuous).stroke(theme.panelBorder, lineWidth: 1))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
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
        .background(theme.panel, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .foregroundStyle(theme.textPrimary)
        .accessibilityElement(children: .combine)
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logros").font(.headline).foregroundStyle(theme.textPrimary)
            ForEach(Achievements.all) { achievement in
                let unlocked = achievement.isUnlocked(stats)
                HStack {
                    Image(systemName: unlocked ? "rosette" : "circle.dashed")
                        .foregroundStyle(unlocked ? theme.accent : theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title).font(.subheadline.weight(.semibold))
                        Text(achievement.detail).font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Text("+\(achievement.xp) XP").font(.caption.monospacedDigit())
                }
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.panel.opacity(unlocked ? 1 : 0.6), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(achievement.title). \(unlocked ? "Conseguido" : "Bloqueado"). \(achievement.detail)")
            }
        }
    }

    private var recentTrips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Últimas rutas").font(.headline).foregroundStyle(theme.textPrimary)
            ForEach(trips.prefix(5)) { trip in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.destinationName).font(.subheadline.weight(.semibold))
                        Text(trip.startedAt, style: .date).font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Text(Formatters.distance(trip.distanceMeters, metric: true)).font(.caption.monospacedDigit())
                }
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            }
        }
    }
}
