import SwiftData
import XCTest
@testable import QuestMapIRL

@MainActor
final class GeneratedVoicePackTests: XCTestCase {
    private var dir: URL!
    private var keep: [ModelContainer] = []
    private let girl = GeneratedVoicePacks.all.first { $0.gender == .girl }!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        keep.removeAll()
        try? FileManager.default.removeItem(at: dir)
    }

    /// Escribe un índice y archivos (contenido ficticio: aquí solo se comprueba la existencia).
    private func writePack(_ info: GeneratedVoicePackInfo, phrases: [VoicePhraseID], skipFiles: Set<VoicePhraseID> = [],
                           id: String? = nil) throws {
        var entries: [String: Any] = [:]
        for phrase in phrases {
            let file = "\(info.slug)-\(phrase.rawValue.replacingOccurrences(of: ".", with: "_")).m4a"
            entries[phrase.rawValue] = ["file": file, "start": 0.05, "end": 1.1, "gain": 1.2]
            if !skipFiles.contains(phrase) {
                FileManager.default.createFile(atPath: dir.appendingPathComponent(file).path, contents: Data("aac".utf8))
            }
        }
        let index: [String: Any] = ["format": 1, "id": id ?? info.id, "catalog_version": VoicePromptCatalog.version,
                                    "voice_name": "Prueba", "phrases": entries]
        try JSONSerialization.data(withJSONObject: index).write(to: dir.appendingPathComponent("\(info.slug).voicepack.json"))
    }

    private var everything: [VoicePhraseID] { VoicePhraseID.allCases }

    func testTwoSpanishPacksOneGirlOneBoyWithUniqueFilePrefixes() {
        XCTAssertEqual(GeneratedVoicePacks.all.count, 2)
        XCTAssertEqual(Set(GeneratedVoicePacks.all.map(\.gender)), [.girl, .boy])
        XCTAssertTrue(GeneratedVoicePacks.all.allSatisfy { $0.languageCode == "es-ES" && !$0.summary.isEmpty })
        XCTAssertEqual(Set(GeneratedVoicePacks.all.map(\.slug)).count, 2)
        XCTAssertTrue(GeneratedVoicePacks.all.allSatisfy { $0.provenance.contains("IA") })
    }

    func testPackNotShippedIsNotIncludedAndNeverReady() {
        let pack = GeneratedVoicePackLoader(resourceURL: dir).pack(girl)
        XCTAssertEqual(pack.availability, .notIncluded)
        XCTAssertTrue(pack.segments.isEmpty)
        XCTAssertTrue(pack.demoSegments.isEmpty)
    }

    func testCompletePackIsReadyWithTimingsAndDemo() throws {
        try writePack(girl, phrases: everything)
        let pack = GeneratedVoicePackLoader(resourceURL: dir).pack(girl)
        XCTAssertEqual(pack.availability, .ready)
        XCTAssertEqual(pack.segments.count, VoicePhraseID.allCases.count)
        let segment = try XCTUnwrap(pack.segments[.turnRight])
        XCTAssertEqual(segment.start, 0.05)
        XCTAssertEqual(segment.end, 1.1)
        XCTAssertEqual(segment.gain, 1.2)
        XCTAssertEqual(pack.demoSegments.count, 2)
    }

    func testMissingRequiredFileMakesThePackUnavailable() throws {
        try writePack(girl, phrases: everything, skipFiles: [.turnRight, .in200m])
        let pack = GeneratedVoicePackLoader(resourceURL: dir).pack(girl)
        XCTAssertEqual(pack.availability, .incomplete(missingRequired: 2))
        XCTAssertFalse(pack.availability.isReady)
        XCTAssertNil(pack.segments[.turnRight], "un archivo ausente no se reproduce")
    }

    func testOptionalPhrasesMissingStillReady() throws {
        let required = Array(VoicePromptCatalog.requiredIDs(language: "es-ES"))
        try writePack(girl, phrases: required)
        XCTAssertEqual(GeneratedVoicePackLoader(resourceURL: dir).pack(girl).availability, .ready)
    }

    func testDamagedOrForeignIndexIsRejected() throws {
        FileManager.default.createFile(atPath: dir.appendingPathComponent("\(girl.slug).voicepack.json").path,
                                       contents: Data("<html>error</html>".utf8))
        XCTAssertEqual(GeneratedVoicePackLoader(resourceURL: dir).pack(girl).availability, .damaged)
        try writePack(girl, phrases: everything, id: "otro-paquete")
        XCTAssertEqual(GeneratedVoicePackLoader(resourceURL: dir).pack(girl).availability, .damaged)
    }

    private func open() throws -> ModelContext {
        let url = dir.appendingPathComponent("db.store")
        let container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(schema: AppSchema.schema, url: url))
        keep.append(container)
        return ModelContext(container)
    }

    func testSelectionPersistsAndExcludesRecordedProfiles() throws {
        do {
            let context = try open()
            let settings = UserSettings()
            context.insert(settings)
            settings.activeVoiceProfileID = UUID()
            settings.activeGeneratedVoicePackID = girl.id
            XCTAssertNil(settings.activeVoiceProfileID, "elegir un paquete deselecciona el perfil grabado")
            XCTAssertFalse(settings.usesSystemVoice)
            try PersistenceCommit.save(context)
        }
        let reopened = try open()                         // como reiniciar la app
        let settings = try XCTUnwrap(try reopened.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.activeGeneratedVoicePackID, girl.id)
        settings.activeVoiceProfileID = nil                 // «Voz del sistema»
        XCTAssertTrue(settings.usesSystemVoice)
        XCTAssertNil(settings.activeGeneratedVoicePackID)
    }

    func testActivePackFeedsNavigationOnlyWhenReady() throws {
        let context = try open()
        let settings = UserSettings()
        context.insert(settings)
        settings.activeGeneratedVoicePackID = girl.id
        try PersistenceCommit.save(context)
        let files = VoiceRecordingFiles(baseURL: dir.appendingPathComponent("VoiceProfiles"))
        XCTAssertNil(AppEnvironment.activeRecordedVoice(context: context, files: files,
                                                        packs: GeneratedVoicePackLoader(resourceURL: dir)),
                     "sin audios: voz del sistema")
        try writePack(girl, phrases: everything)
        let source = try XCTUnwrap(AppEnvironment.activeRecordedVoice(context: context, files: files,
                                                                      packs: GeneratedVoicePackLoader(resourceURL: dir)))
        XCTAssertEqual(source.segments.count, VoicePhraseID.allCases.count)
        XCTAssertTrue(source.fallbackOnFailure)
    }

    func testDamagedFileFallsBackToSystemVoiceEvenWithRecordingsOnly() {
        let synthesizer = FakeSynthesizer()
        let player = FakeRecordedPlayer()
        player.fails = true
        let voice = NavigationVoice(defaults: UserDefaults(suiteName: "gp-\(UUID().uuidString)")!, synthesizer: synthesizer,
                                    session: FakeSession(), voices: { [] }, observeSystemEvents: false, recordedPlayer: player)
        let segment = VoicePromptSegment(url: URL(fileURLWithPath: "/tmp/x.m4a"), start: 0, end: 1, gain: 1)
        voice.recordedVoice = {
            RecordedVoiceSource(segments: [.in200m: segment, .turnRight: segment], strategy: .recordingsOnly, fallbackOnFailure: true)
        }
        let cue = VoiceCue(text: "En 200 metros, gira a la derecha", phrases: [.in200m, .turnRight])
        voice.announce(cue)
        XCTAssertEqual(synthesizer.spoken.map(\.speechString), [cue.text], "nunca sin voz por un archivo dañado")
    }

    func testShippedIndexesInTheAppBundleAreValidWhenPresent() {
        for info in GeneratedVoicePacks.all {
            let pack = GeneratedVoicePackLoader(resourceURL: Bundle.main.resourceURL).pack(info)
            XCTAssertNotEqual(pack.availability, .damaged, "\(info.id): índice incluido pero ilegible")
        }
    }
}
