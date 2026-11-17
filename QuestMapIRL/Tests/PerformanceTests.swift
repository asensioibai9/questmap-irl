import SwiftData
import UIKit
import XCTest
@testable import QuestMapIRL

/// Comprobaciones de las optimizaciones (lógica, no tiempos: los tiempos del simulador de CI no valen como medida de un
/// iPhone real).
@MainActor
final class PerformanceTests: XCTestCase {
    // MARK: Causa del bloqueo en Ajustes: lista de voces instaladas

    func testInstalledVoicesAreReadOnceNotOnEveryRedraw() {
        var reads = 0
        var installed = [testVoice("a", quality: 2, gender: .girl)]
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "perf-\(UUID().uuidString)")!, synthesizer: FakeSynthesizer(),
                                    session: FakeSession(), voices: { reads += 1; return installed }, observeSystemEvents: false)
        // Lo que lee Ajustes de navegación en cada redibujado.
        for _ in 0..<20 {
            _ = voice.statusText
            _ = voice.voiceDetails
            _ = voice.warning
            _ = voice.onlyBasicVoicesInstalled
            _ = voice.voiceChoices
            _ = voice.selection
        }
        XCTAssertEqual(reads, 1, "antes: ~6 lecturas del sistema por redibujado")
        installed.append(testVoice("b", quality: 3, gender: .girl))
        voice.refreshVoices()                          // volver a la app / voces nuevas
        XCTAssertEqual(voice.selection.voice?.identifier, "b")
        XCTAssertEqual(reads, 2)
        _ = voice.makeUtterance("Gira a la derecha")   // cada indicación tampoco vuelve a leer la lista
        XCTAssertEqual(reads, 2)
    }

    // MARK: Escrituras idénticas

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        keep.append(container)
        return ModelContext(container)
    }
    private var keep: [ModelContainer] = []

    func testChoosingTheSameSignOptionDoesNotWriteAnything() throws {
        let context = try context()
        let settings = UserSettings()
        context.insert(settings)
        try PersistenceCommit.save(context)
        XCTAssertFalse(context.hasChanges)
        let same = settings.speedSignAppearance
        settings.speedSignAppearance = same                                  // misma opción
        XCTAssertFalse(context.hasChanges, "no se marca nada como cambiado")
        var other = settings.speedSignAppearance
        other.style = .minimal
        settings.speedSignAppearance = other
        XCTAssertTrue(context.hasChanges)
        try PersistenceCommit.save(context)
        XCTAssertEqual(settings.speedSignAppearance.style, .minimal)
        XCTAssertNoThrow(try PersistenceCommit.save(context), "guardar sin cambios no hace nada")
    }

    func testRapidSignChangesKeepTheLastChoice() throws {
        let context = try context()
        let settings = UserSettings()
        context.insert(settings)
        for style in [SpeedSignStyle.european, .unitedStates, .minimal, .european, .unitedStates] {
            var value = settings.speedSignAppearance
            value.style = style
            settings.speedSignAppearance = value
            try PersistenceCommit.save(context)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).first?.speedSignAppearance.style, .unitedStates)
    }

    // MARK: Fin de ruta: no se cargan todas las celdas exploradas

    func testTripSaveOnlyAddsNewCellsAndKeepsExistingOnes() throws {
        let context = try context()
        let repository = TripRepository(context: context)
        func summary(_ keys: Set<String>) -> TripSummary {
            TripSummary(startedAt: Date(), distanceMeters: 500, durationSeconds: 60, destinationName: "X", destinationKey: "k",
                        modeRawValue: "driving", visitedKeys: keys)
        }
        try repository.save(summary(["a", "b"]))
        try repository.save(summary(["b", "c"]))
        let keys = Set(try context.fetch(FetchDescriptor<VisitedCell>()).map(\.key))
        XCTAssertEqual(keys, ["a", "b", "c"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripRecord>()), 2)
    }

    // MARK: Previews: decodificadas fuera del hilo principal y al tamaño de la tarjeta

    func testCachedPreviewIsDecodedDownsampled() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let big = UIGraphicsImageRenderer(size: CGSize(width: 1920, height: 1200), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }()).image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1200))
        }
        try XCTUnwrap(big.pngData()).write(to: url)
        let image = try XCTUnwrap(await StylePreviewStore.decodeForDisplay(url: url, maxPixel: 600))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 600)
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 1.6, accuracy: 0.01, "sin deformar")
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("roto-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: broken.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: broken) }
        let decodedBroken = await StylePreviewStore.decodeForDisplay(url: broken, maxPixel: 600)
        XCTAssertNil(decodedBroken, "archivo dañado: se regenera, no se muestra basura")
    }

    // MARK: Instrumentación

    func testSlowOperationsAreLoggedWithoutPersonalData() {
        let result = PerformanceTrace.measure("perf-test-op", thresholdMs: 0) { 41 + 1 }
        XCTAssertEqual(result, 42)
        let event = DiagnosticsLog.shared.events.last { $0.operation == "perf-test-op" }
        XCTAssertEqual(event?.service, "performance")
        XCTAssertEqual(event?.outcome, "slow")
        XCTAssertNil(event?.note)
        XCTAssertEqual(PerformanceTrace.lastOperation?.name, "perf-test-op")
    }
}
