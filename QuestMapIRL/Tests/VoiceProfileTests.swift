import AVFoundation
import CoreLocation
import SwiftData
import XCTest
@testable import QuestMapIRL

// MARK: - Catálogo y correspondencia con el motor

final class VoicePromptCatalogTests: XCTestCase {
    func testCatalogHasStableUniqueIdsAndEveryPhraseHasText() {
        let phrases = VoicePromptCatalog.phrases(language: "es-ES")
        XCTAssertEqual(Set(phrases.map(\.id)).count, phrases.count, "sin duplicados")
        XCTAssertEqual(Set(phrases.map(\.id)), Set(VoicePhraseID.allCases), "toda frase del catálogo tiene id y viceversa")
        XCTAssertTrue(phrases.allSatisfy { !$0.text.isEmpty })
        // Los identificadores son la clave guardada: no pueden cambiar.
        XCTAssertEqual(VoicePhraseID.turnRight.rawValue, "dir.right")
        XCTAssertEqual(VoicePhraseID.in200m.rawValue, "dist.200m")
        XCTAssertEqual(VoicePhraseID.roundaboutExit2.rawValue, "roundabout.exit2")
    }

    func testRequiredSetCoversABasicUrbanRoute() {
        let required = VoicePromptCatalog.requiredIDs(language: "es-ES")
        for id: VoicePhraseID in [.startRoute, .arrived, .recalculating, .turnRight, .turnLeft, .continueStraight,
                                  .in100m, .in200m, .in500m, .roundaboutExit1, .roundaboutExit2, .roundaboutExit3] {
            XCTAssertTrue(required.contains(id), "\(id) debería ser obligatoria")
        }
        XCTAssertFalse(required.contains(.roundaboutExit6), "las opcionales no bloquean el perfil básico")
    }

    private func phrase(_ type: String, _ modifier: String? = nil, exit: Int? = nil) -> VoicePhraseID? {
        VoicePromptComposer.maneuverPhrase(ManeuverInfo(type: type, modifier: modifier, exit: exit))
    }

    func testManeuversFromTheRealEngineMapToTheRightPhrase() {
        XCTAssertEqual(phrase("turn", "right"), .turnRight)
        XCTAssertEqual(phrase("turn", "left"), .turnLeft)
        XCTAssertEqual(phrase("turn", "slight right"), .slightRight)
        XCTAssertEqual(phrase("turn", "sharp left"), .sharpLeft)
        XCTAssertEqual(phrase("turn", "straight"), .continueStraight)
        XCTAssertEqual(phrase("turn", "uturn"), .uTurn)
        XCTAssertEqual(phrase("end of road", "right"), .turnRight)
        XCTAssertEqual(phrase("continue", "slight left"), .keepLeft)
        XCTAssertEqual(phrase("new name"), .continueStraight)
        XCTAssertEqual(phrase("merge", "slight right"), .merge)
        XCTAssertEqual(phrase("on ramp", "right"), .onRampRight)
        XCTAssertEqual(phrase("off ramp", "slight left"), .exitLeft)
        XCTAssertEqual(phrase("fork", "right"), .forkRight)
        XCTAssertEqual(phrase("fork", "straight"), .continueStraight)
        XCTAssertEqual(phrase("roundabout", "right", exit: 3), .roundaboutExit3)
        XCTAssertEqual(phrase("rotary", nil, exit: 1), .roundaboutExit1)
        XCTAssertEqual(phrase("roundabout"), .enterRoundabout)
        XCTAssertEqual(phrase("exit roundabout", "right"), .leaveRoundabout)
        XCTAssertEqual(phrase("arrive", "right"), .destinationRight)
        XCTAssertEqual(phrase("arrive"), .arrived)
    }

    func testNoPhraseIsInventedForUnsupportedOrUnknownData() {
        XCTAssertNil(phrase("roundabout", "right", exit: 7), "séptima salida: nunca otro número")
        XCTAssertNil(phrase("roundabout turn", "left"))
        XCTAssertNil(phrase("turn", nil), "giro sin dirección")
        XCTAssertNil(phrase("on ramp"), "incorporación sin lado")
        XCTAssertNil(phrase("something new"))
        XCTAssertNil(VoicePromptComposer.maneuverPhrase(nil), "ruta sin datos de maniobra")
    }

    func testDistancesOnlyMatchWhenTheyAreNotClearlyFalse() {
        func d(_ meters: Double, metric: Bool = true) -> VoicePhraseID?? { VoicePromptComposer.distancePhrase(meters: meters, metric: metric) }
        XCTAssertEqual(d(175), .some(.in200m), "aviso de la banda de 180 m")
        XCTAssertEqual(d(545), .some(.in500m), "aviso de la banda de 550 m")
        XCTAssertEqual(d(160), .some(.in200m))
        XCTAssertEqual(d(95), .some(.in100m))
        XCTAssertEqual(d(2100), .some(.in2km))
        XCTAssertEqual(d(30), .some(nil), "muy cerca: solo la maniobra")
        XCTAssertNil(d(1234), "no se dice «en un kilómetro» a 1,2 km")
        XCTAssertNil(d(650), "entre 500 y 800: ninguna es correcta")
        XCTAssertNil(d(400, metric: false), "en millas no hay grabaciones")
    }

    private func step(_ type: String, _ modifier: String? = nil, exit: Int? = nil, variable: Bool = false) -> RouteStep {
        RouteStep(instruction: "x", distanceMeters: 100, symbol: "arrow.up", streetName: "Calle Mayor",
                  maneuver: ManeuverInfo(type: type, modifier: modifier, exit: exit, hasVariableDetail: variable))
    }

    func testCueComposesDistancePlusManeuverAndKeepsTheSystemTextUnchanged() {
        let cue = VoicePromptComposer.maneuverCue(step: step("turn", "right"), instruction: "Gira a la derecha en Calle Mayor",
                                                  distance: 175, metric: true)
        XCTAssertEqual(cue.text, ManeuverFormatter.spoken(instruction: "Gira a la derecha en Calle Mayor", distance: 175, metric: true))
        XCTAssertEqual(cue.phrases, [.in200m, .turnRight])
        let close = VoicePromptComposer.maneuverCue(step: step("roundabout", "right", exit: 2), instruction: "En la rotonda…", distance: 20, metric: true)
        XCTAssertEqual(close.phrases, [.roundaboutExit2])
    }

    func testArrivalIsOnlySaidWithRecordingsWhenTheEngineConfirmsIt() {
        let approaching = VoicePromptComposer.maneuverCue(step: step("arrive"), instruction: "Has llegado a tu destino", distance: 175, metric: true)
        XCTAssertNil(approaching.phrases, "al acercarse no se graba «has llegado»")
        let side = VoicePromptComposer.maneuverCue(step: step("arrive", "left"), instruction: "Has llegado, a la izquierda", distance: 175, metric: true)
        XCTAssertEqual(side.phrases, [.in200m, .destinationLeft])
    }

    func testNumberedExitPrefersTheSystemVoiceInHybrid() {
        let cue = VoicePromptComposer.maneuverCue(step: step("off ramp", "right", variable: true), instruction: "Toma la salida 23 a la derecha",
                                                  distance: 500, metric: true)
        XCTAssertTrue(cue.systemSaysMore)
        let all = Set(VoicePhraseID.allCases)
        XCTAssertEqual(VoicePlaybackPlanner.plan(cue, available: all, strategy: .hybrid), .system(cue.text))
        XCTAssertEqual(VoicePlaybackPlanner.plan(cue, available: all, strategy: .recordingsOnly), .recordings([.in500m, .exitRight]))
    }

    func testFallbackNeverMixesVoicesWithinAPhrase() {
        let cue = VoiceCue(text: "En 200 metros, gira a la derecha", phrases: [.in200m, .turnRight])
        XCTAssertEqual(VoicePlaybackPlanner.plan(cue, available: [.in200m, .turnRight], strategy: .hybrid), .recordings([.in200m, .turnRight]))
        XCTAssertEqual(VoicePlaybackPlanner.plan(cue, available: [.in200m], strategy: .hybrid), .system(cue.text), "falta una: la frase ENTERA con el sistema")
        XCTAssertEqual(VoicePlaybackPlanner.plan(cue, available: [.in200m], strategy: .recordingsOnly), .silent)
        XCTAssertEqual(VoicePlaybackPlanner.plan(.text("Gira en Calle X"), available: Set(VoicePhraseID.allCases), strategy: .hybrid),
                       .system("Gira en Calle X"))
    }

    func testProgressAndActivationRules() {
        let required = VoicePromptCatalog.requiredIDs(language: "es-ES")
        let partial = VoiceProfileProgress.make(recorded: [.turnRight], language: "es-ES")
        XCTAssertFalse(partial.isReady)
        XCTAssertEqual(partial.recorded, 1)
        XCTAssertTrue(partial.canActivate(strategy: .hybrid), "incompleto + respaldo del sistema")
        XCTAssertFalse(partial.canActivate(strategy: .recordingsOnly))
        XCTAssertFalse(VoiceProfileProgress.make(recorded: [], language: "es-ES").canActivate(strategy: .hybrid))
        let full = VoiceProfileProgress.make(recorded: required, language: "es-ES")
        XCTAssertTrue(full.isReady, "las opcionales no hacen falta")
        XCTAssertTrue(full.canActivate(strategy: .recordingsOnly))
    }
}

// MARK: - Validación del audio

final class AudioQualityAnalyzerTests: XCTestCase {
    private let rate = 44_100.0

    private func tone(seconds: Double, amplitude: Float, leadingSilence: Double = 0, trailingSilence: Double = 0) -> [Float] {
        let silence = { (s: Double) in [Float](repeating: 0, count: Int(s * self.rate)) }
        let body = (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / rate)) }
        return silence(leadingSilence) + body + silence(trailingSilence)
    }

    func testGoodRecordingPassesAndFindsWhereTheVoiceIs() {
        let result = AudioQualityAnalyzer.analyze(samples: tone(seconds: 0.8, amplitude: 0.3, leadingSilence: 0.5, trailingSilence: 0.4), sampleRate: rate)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        XCTAssertTrue(result.canSave)
        XCTAssertEqual(result.speechStart, 0.5 - AudioQualityAnalyzer.leadMargin, accuracy: 0.02)
        XCTAssertEqual(result.speechEnd, 1.3 + AudioQualityAnalyzer.tailMargin, accuracy: 0.02)
        XCTAssertLessThanOrEqual(result.peak * result.playbackGain, AudioQualityAnalyzer.maxPeakAfterGain + 1e-6, "sin distorsión")
    }

    func testEmptyShortLongAndSilentRecordingsCannotBeSaved() {
        XCTAssertTrue(AudioQualityAnalyzer.analyze(samples: [Float](repeating: 0, count: Int(rate)), sampleRate: rate).issues.contains(.empty))
        XCTAssertTrue(AudioQualityAnalyzer.analyze(samples: tone(seconds: 0.1, amplitude: 0.3), sampleRate: rate).issues.contains(.tooShort))
        XCTAssertTrue(AudioQualityAnalyzer.analyze(samples: tone(seconds: 11, amplitude: 0.3), sampleRate: rate).issues.contains(.tooLong))
        let blip = AudioQualityAnalyzer.analyze(samples: tone(seconds: 0.1, amplitude: 0.3, leadingSilence: 1, trailingSilence: 1), sampleRate: rate)
        XCTAssertTrue(blip.issues.contains(.noSpeech))
        XCTAssertFalse(blip.canSave)
    }

    func testQuietAndClippedRecordingsWarnButAmplificationIsCapped() {
        let quiet = AudioQualityAnalyzer.analyze(samples: tone(seconds: 1, amplitude: 0.015, leadingSilence: 0.2), sampleRate: rate)
        XCTAssertTrue(quiet.issues.contains(.tooQuiet))
        XCTAssertTrue(quiet.canSave, "aviso, no bloqueo")
        XCTAssertEqual(quiet.playbackGain, AudioQualityAnalyzer.maxGain, accuracy: 1e-9, "no se amplifica más de +12 dB")
        let clipped = AudioQualityAnalyzer.analyze(samples: tone(seconds: 1, amplitude: 1.4).map { max(-1, min(1, $0)) }, sampleRate: rate)
        XCTAssertTrue(clipped.issues.contains(.clipping))
    }

    func testUnreadableFileIsReportedNotCrashed() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roto-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data("no es audio".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(AudioQualityAnalyzer.analyze(fileAt: url).issues, [.unreadable])
    }
}

// MARK: - Perfiles: persistencia y archivos

@MainActor
final class VoiceProfileStoreTests: XCTestCase {
    private var dir: URL!
    private var keep: [ModelContainer] = []
    private let analysis = AudioAnalysis(duration: 1.2, peak: 0.5, speechLevelDB: -22, clippedFraction: 0, speechStart: 0.1,
                                         speechEnd: 1.1, playbackGain: 1.2, issues: [])

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        keep.removeAll()
        try? FileManager.default.removeItem(at: dir)
    }

    private func open() throws -> ModelContext {
        let url = dir.appendingPathComponent("db.store")
        let container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
        keep.append(container)
        return ModelContext(container)
    }

    private func store(_ context: ModelContext) -> VoiceProfileStore {
        VoiceProfileStore(context: context, files: VoiceRecordingFiles(baseURL: dir.appendingPathComponent("VoiceProfiles")))
    }

    private func tempRecording(_ content: String = "audio") -> URL {
        let url = dir.appendingPathComponent("tmp-\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8))
        return url
    }

    func testProfileAndRecordingsSurviveReopeningAndProgressContinues() throws {
        var id: UUID
        do {
            let s = store(try open())
            let profile = try s.createProfile(name: "  Voz de Ibai  ")
            XCTAssertEqual(profile.name, "Voz de Ibai")
            id = profile.profileID
            try s.saveRecording(profileID: id, phrase: .turnRight, from: tempRecording(), analysis: analysis)
            try s.saveRecording(profileID: id, phrase: .in200m, from: tempRecording(), analysis: analysis)
        }
        let s = store(try open())                 // como cerrar y abrir la app
        let profile = try XCTUnwrap(s.profile(id: id))
        XCTAssertEqual(profile.languageCode, "es-ES")
        XCTAssertEqual(profile.catalogVersion, VoicePromptCatalog.version)
        XCTAssertEqual(s.recordedPhrases(for: id), [.turnRight, .in200m])
        XCTAssertEqual(s.progress(for: profile).recorded, 2)
        XCTAssertFalse(s.progress(for: profile).isReady)
        let segment = try XCTUnwrap(s.segments(for: id)[.turnRight])
        XCTAssertEqual(segment.start, 0.1)
        XCTAssertEqual(segment.gain, 1.2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: segment.url.path))
    }

    func testReRecordingReplacesTheFileOnlyAfterSavingAndDeletingMakesItPending() throws {
        let s = store(try open())
        let id = try s.createProfile(name: "Mi voz").profileID
        try s.saveRecording(profileID: id, phrase: .turnLeft, from: tempRecording("uno"), analysis: analysis)
        let first = try XCTUnwrap(s.segments(for: id)[.turnLeft]).url
        try s.saveRecording(profileID: id, phrase: .turnLeft, from: tempRecording("dos"), analysis: analysis)
        let second = try XCTUnwrap(s.segments(for: id)[.turnLeft]).url
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "la anterior se borra tras guardar la nueva")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "dos")
        XCTAssertEqual(try s.recordings(for: id).count, 1, "una grabación por frase")
        try s.deleteRecording(profileID: id, phrase: .turnLeft)
        XCTAssertTrue(s.recordedPhrases(for: id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testFailedSaveKeepsThePreviousRecording() throws {
        let s = store(try open())
        let id = try s.createProfile(name: "Mi voz").profileID
        try s.saveRecording(profileID: id, phrase: .arrived, from: tempRecording("buena"), analysis: analysis)
        let before = try XCTUnwrap(s.segments(for: id)[.arrived]).url
        XCTAssertThrowsError(try s.saveRecording(profileID: id, phrase: .arrived,
                                                 from: dir.appendingPathComponent("no-existe.m4a"), analysis: analysis)) { error in
            XCTAssertEqual(error as? VoiceStoreError, .missingRecording)
        }
        if s.files.availableCapacity() != nil {
            s.minimumFreeBytes = .max                 // simula un iPhone lleno
            XCTAssertThrowsError(try s.saveRecording(profileID: id, phrase: .arrived, from: tempRecording("nueva"), analysis: analysis)) { error in
                XCTAssertEqual(error as? VoiceStoreError, .notEnoughSpace)
            }
        }
        XCTAssertEqual(try XCTUnwrap(s.segments(for: id)[.arrived]).url, before)
        XCTAssertEqual(try String(contentsOf: before, encoding: .utf8), "buena")
    }

    func testMissingOrDamagedFileCountsAsPendingAndIsNotPlayed() throws {
        let s = store(try open())
        let id = try s.createProfile(name: "Mi voz").profileID
        try s.saveRecording(profileID: id, phrase: .turnRight, from: tempRecording(), analysis: analysis)
        let url = try XCTUnwrap(s.segments(for: id)[.turnRight]).url
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(s.recordedPhrases(for: id).isEmpty)
        XCTAssertNil(s.segments(for: id)[.turnRight])
    }

    func testDeletingTheActiveProfileReturnsToTheSystemVoiceAndRemovesItsFiles() throws {
        let context = try open()
        let s = store(context)
        let settings = UserSettings()
        context.insert(settings)
        let profile = try s.createProfile(name: "Mi voz")
        let id = profile.profileID
        try s.saveRecording(profileID: id, phrase: .turnRight, from: tempRecording(), analysis: analysis)
        settings.activeVoiceProfileID = id
        try PersistenceCommit.save(context)
        XCTAssertNotNil(AppEnvironment.activeRecordedVoice(context: context, files: s.files))
        try s.delete(profile, settings: settings)
        XCTAssertNil(settings.activeVoiceProfileID)
        XCTAssertNil(AppEnvironment.activeRecordedVoice(context: context, files: s.files), "sin referencias a archivos inexistentes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.files.directory(for: id).path))
        XCTAssertTrue(try s.recordings(for: id).isEmpty)
    }

    func testIncompleteProfileNeverSilencesEssentialsEvenWithRecordingsOnly() throws {
        let context = try open()
        let s = store(context)
        let settings = UserSettings()
        settings.voiceFallback = .recordingsOnly
        context.insert(settings)
        let id = try s.createProfile(name: "Mi voz").profileID
        try s.saveRecording(profileID: id, phrase: .turnRight, from: tempRecording(), analysis: analysis)
        settings.activeVoiceProfileID = id
        try PersistenceCommit.save(context)
        XCTAssertEqual(AppEnvironment.activeRecordedVoice(context: context, files: s.files)?.strategy, .hybrid)
    }

    func testOrphanCleanupNeverTouchesReferencedFiles() throws {
        let s = store(try open())
        let id = try s.createProfile(name: "Mi voz").profileID
        try s.saveRecording(profileID: id, phrase: .turnRight, from: tempRecording(), analysis: analysis)
        let kept = try XCTUnwrap(s.segments(for: id)[.turnRight]).url
        let orphan = s.files.directory(for: id).appendingPathComponent("huerfano.m4a")
        FileManager.default.createFile(atPath: orphan.path, contents: Data("x".utf8))
        let ghostFolder = s.files.baseURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: ghostFolder, withIntermediateDirectories: true)
        XCTAssertEqual(s.cleanupOrphans(), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ghostFolder.path))
    }

    func testEmptyNameIsRejected() throws {
        let s = store(try open())
        XCTAssertThrowsError(try s.createProfile(name: "   ")) { XCTAssertEqual($0 as? VoiceStoreError, .invalidName) }
    }
}

// MARK: - Reproducción durante la navegación

@MainActor
final class FakeRecordedPlayer: RecordedPromptPlaying {
    private(set) var isPlaying = false
    private(set) var played: [[VoicePromptSegment]] = []
    private var completion: (@MainActor (Bool) -> Void)?
    var fails = false

    func play(_ segments: [VoicePromptSegment], volume: Float, completion: @escaping @MainActor (Bool) -> Void) throws {
        if fails { throw RecordedPromptError.unreadable }
        played.append(segments)
        isPlaying = true
        self.completion = completion
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        let pending = completion
        completion = nil
        pending?(false)
    }

    func finish() {
        guard isPlaying else { return }
        isPlaying = false
        let pending = completion
        completion = nil
        pending?(true)
    }
}

@MainActor
final class RecordedVoiceNavigationTests: XCTestCase {
    private let synthesizer = FakeSynthesizer()
    private let session = FakeSession()
    private let player = FakeRecordedPlayer()
    private var strategy = VoiceFallbackStrategy.hybrid
    private var available: [VoicePhraseID] = [.in200m, .turnRight, .recalculating, .startRoute]
    private var profileActive = true

    private func segment(_ id: VoicePhraseID) -> VoicePromptSegment {
        VoicePromptSegment(url: URL(fileURLWithPath: "/tmp/\(id.rawValue).m4a"), start: 0, end: 1, gain: 1)
    }

    private func makeVoice() -> NavigationVoice {
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "rv-\(UUID().uuidString)")!, synthesizer: synthesizer,
                                    session: session, voices: { [] }, observeSystemEvents: false, recordedPlayer: player)
        voice.recordedVoice = { [unowned self] in
            guard self.profileActive else { return nil }
            return RecordedVoiceSource(segments: Dictionary(uniqueKeysWithValues: self.available.map { ($0, self.segment($0)) }),
                                       strategy: self.strategy)
        }
        return voice
    }

    private let turn = VoiceCue(text: "En 200 metros, gira a la derecha", phrases: [.in200m, .turnRight])

    func testRecordedInstructionPlaysTheSequenceAndNotTheSystemVoice() {
        let voice = makeVoice()
        voice.announce(turn)
        XCTAssertEqual(player.played, [[segment(.in200m), segment(.turnRight)]])
        XCTAssertTrue(synthesizer.spoken.isEmpty, "nunca dos motores")
        player.finish()
        XCTAssertGreaterThanOrEqual(session.deactivateCount, 1, "se devuelve el audio a la música al terminar")
    }

    func testMissingPhraseUsesTheWholeSystemSentenceInHybridAndNothingInRecordingsOnly() {
        available = [.in200m]
        let voice = makeVoice()
        voice.announce(turn)
        XCTAssertTrue(player.played.isEmpty)
        XCTAssertEqual(synthesizer.spoken.map(\.speechString), [turn.text])
        strategy = .recordingsOnly
        let other = makeVoice()
        synthesizer.spoken.removeAll()
        other.announce(VoiceCue(text: "En 500 metros, gira a la izquierda", phrases: [.in500m, .turnLeft]))
        XCTAssertTrue(synthesizer.spoken.isEmpty)
        XCTAssertTrue(player.played.isEmpty)
    }

    func testWithoutActiveProfileEverythingIsAsBefore() {
        profileActive = false
        let voice = makeVoice()
        voice.announce(turn)
        XCTAssertEqual(synthesizer.spoken.map(\.speechString), [turn.text])
        XCTAssertTrue(player.played.isEmpty)
    }

    func testNewInstructionCancelsTheObsoleteOneAndRecalculationDropsPendingTurns() {
        let voice = makeVoice()
        voice.announce(VoiceCue(text: "Empezamos la ruta hacia Casa.", phrases: [.startRoute]))
        voice.announce(turn, interrupt: false)                       // espera su turno
        XCTAssertEqual(player.played.count, 1)
        voice.announce(VoiceCue(text: "Recalculando la ruta.", phrases: [.recalculating]), interrupt: true)
        XCTAssertEqual(player.played.last, [segment(.recalculating)])
        player.finish()
        XCTAssertEqual(player.played.count, 2, "el giro pendiente de la ruta anterior no se reproduce")
    }

    func testQueuedInstructionPlaysAfterTheCurrentOneWithoutOverlapping() {
        let voice = makeVoice()
        voice.announce(VoiceCue(text: "Empezamos la ruta hacia Casa.", phrases: [.startRoute]))
        voice.announce(turn, interrupt: false)
        XCTAssertEqual(player.played.count, 1)
        player.finish()
        XCTAssertEqual(player.played.count, 2)
        XCTAssertEqual(player.played.last, [segment(.in200m), segment(.turnRight)])
    }

    func testDuplicatesMuteAndStopAreRespected() {
        let voice = makeVoice()
        voice.announce(turn)
        player.finish()
        voice.announce(turn)
        XCTAssertEqual(player.played.count, 1, "no se repite la misma indicación")
        voice.announce(VoiceCue(text: "Empezamos la ruta hacia Casa.", phrases: [.startRoute]))
        voice.announce(turn, interrupt: false)
        voice.stopImmediately()                                       // fin de la ruta
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.played.count, 2, "lo pendiente se descarta al terminar")
        voice.toggleMute()
        voice.announce(VoiceCue(text: "Recalculando la ruta.", phrases: [.recalculating]))
        XCTAssertEqual(player.played.count, 2)
    }

    func testDamagedFileFallsBackToTheSystemVoiceInHybrid() {
        player.fails = true
        let voice = makeVoice()
        voice.announce(turn)
        XCTAssertEqual(synthesizer.spoken.map(\.speechString), [turn.text])
    }

    func testDemoIsMarkedAsATestAndStopsWithTheTestButton() {
        let voice = makeVoice()
        voice.playRecordedDemo([segment(.in200m), segment(.turnRight)])
        XCTAssertTrue(voice.isPlayingTest)
        voice.toggleTest()
        XCTAssertFalse(voice.isPlayingTest)
        XCTAssertFalse(player.isPlaying)
    }

    func testNavigationUsesTheStructuredManeuverForTheRecordedVersion() {
        let voice = makeVoice()
        let points = [CLLocationCoordinate2D(latitude: 40.4000, longitude: -3.7000), CLLocationCoordinate2D(latitude: 40.4050, longitude: -3.7000),
                      CLLocationCoordinate2D(latitude: 40.4100, longitude: -3.7000)]
        let route = Route(name: "Prueba", coordinates: points, distanceMeters: 1110, durationSeconds: 120, steps: [
            RouteStep(instruction: "Empieza la ruta", distanceMeters: 555, symbol: "arrow.up", streetName: "",
                      maneuver: ManeuverInfo(type: "depart")),
            RouteStep(instruction: "Gira a la derecha", distanceMeters: 555, symbol: "arrow.turn.up.right", streetName: "",
                      maneuver: ManeuverInfo(type: "turn", modifier: "right")),
            RouteStep(instruction: "Has llegado a tu destino", distanceMeters: 0, symbol: "flag", streetName: "",
                      maneuver: ManeuverInfo(type: "arrive")),
        ])
        struct NoRoutes: RouteServiceProtocol {
            func routes(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, mode: RouteMode) async throws -> [Route] { [] }
        }
        let navigation = ActiveNavigationViewModel(route: route, destinationName: "Casa", destination: points[2], mode: .driving,
                                                   routeService: NoRoutes(), speech: voice, useMetric: true)
        navigation.start()
        XCTAssertEqual(player.played.first, [segment(.startRoute)], "«Iniciando ruta» con tu voz")
        // A unos 175 m del giro (la maniobra está en el punto intermedio).
        let near = CLLocationCoordinate2D(latitude: 40.4050 - 175 / 111_320, longitude: -3.7000)
        navigation.update(with: CLLocation(coordinate: near, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date()))
        player.finish()
        XCTAssertTrue(player.played.contains([segment(.in200m), segment(.turnRight)]), "\(player.played)")
    }
}
