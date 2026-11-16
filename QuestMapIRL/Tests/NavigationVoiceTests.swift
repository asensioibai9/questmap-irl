import XCTest
import AVFoundation
@testable import QuestMapIRL

// MARK: - Dobles de prueba

private final class FakeSynthesizer: SpeechSynthesizing {
    var isSpeaking = false
    var spoken: [AVSpeechUtterance] = []
    var stopCount = 0

    func speak(_ utterance: AVSpeechUtterance) { spoken.append(utterance) }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCount += 1
        return true
    }
}

private final class FakeSession: AudioSessionControlling {
    var configureCount = 0
    var activateCount = 0
    var deactivateCount = 0

    func configure() throws { configureCount += 1 }
    func activate() throws { activateCount += 1 }
    func deactivate() { deactivateCount += 1 }
}

private func voice(_ id: String, name: String = "V", lang: String = "es-ES", quality: Int = 1,
                   gender: NavigationVoiceGender?) -> VoiceInfo {
    VoiceInfo(identifier: id, name: name, language: lang, quality: quality, gender: gender)
}

@MainActor
final class NavigationVoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "NavigationVoiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeVoice(voices: [VoiceInfo] = [], synthesizer: FakeSynthesizer = FakeSynthesizer(),
                           session: FakeSession = FakeSession()) -> NavigationVoice {
        NavigationVoice(defaults: defaults, synthesizer: synthesizer, session: session, voices: { voices })
    }

    // MARK: Preferencia

    func testDefaultIsGirl() {
        XCTAssertEqual(makeVoice().gender, .girl)
    }

    func testChoosingBoyOrGirlChangesSelectionAndIsSaved() {
        let voice = makeVoice()
        voice.gender = .boy
        XCTAssertEqual(voice.gender, .boy)
        XCTAssertEqual(defaults.string(forKey: NavigationVoice.genderKey), "boy")

        // Una instancia nueva (otro arranque de la app) recupera la preferencia.
        XCTAssertEqual(makeVoice().gender, .boy)

        voice.gender = .girl
        XCTAssertEqual(makeVoice().gender, .girl)
    }

    func testResetPreferencesRemovesStoredValues() {
        let voice = makeVoice()
        voice.gender = .boy
        voice.volume = 0.4
        voice.resetPreferences()
        XCTAssertEqual(voice.gender, .girl)
        XCTAssertNil(defaults.object(forKey: NavigationVoice.genderKey))
        XCTAssertNil(defaults.object(forKey: NavigationVoice.volumeKey))
    }

    func testChangingVoiceAppliesToTheNextAnnouncement() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Gira a la derecha.")
        voice.gender = .boy
        voice.announce("Gira a la izquierda.")
        XCTAssertEqual(synthesizer.spoken.count, 2)
        XCTAssertEqual(synthesizer.spoken[0].pitchMultiplier, NavigationVoiceGender.girl.pitch, accuracy: 0.001)
        XCTAssertEqual(synthesizer.spoken[1].pitchMultiplier, NavigationVoiceGender.boy.pitch, accuracy: 0.001)
    }

    // MARK: Frase y parámetros de la voz

    func testTestPhraseIsSpokenWithExpectedParameters() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.playTest()

        XCTAssertEqual(NavigationVoice.testPhrase, "Prueba de voz. En doscientos metros, gira a la derecha.")
        let utterance = try? XCTUnwrap(synthesizer.spoken.first)
        XCTAssertEqual(utterance?.speechString, NavigationVoice.testPhrase)
        XCTAssertEqual(utterance?.rate ?? 0, 0.48, accuracy: 0.0001)
        XCTAssertTrue(utterance?.voice?.language.hasPrefix("es") ?? false)
    }

    func testBoyPitchIsLowerThanGirlPitch() {
        XCTAssertLessThan(NavigationVoiceGender.boy.pitch, 1)
        XCTAssertGreaterThan(NavigationVoiceGender.girl.pitch, 1)
    }

    func testTestButtonSoundsEvenWhenGuidanceIsMuted() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.isMuted = true
        voice.announce("Gira a la derecha.")
        XCTAssertTrue(synthesizer.spoken.isEmpty)
        voice.playTest()
        XCTAssertEqual(synthesizer.spoken.count, 1)
    }

    // MARK: Comportamiento

    func testNewInstructionCancelsTheCurrentOne() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Primera.")
        voice.announce("Segunda.")
        XCTAssertEqual(synthesizer.stopCount, 2)
        XCTAssertEqual(synthesizer.spoken.map(\.speechString), ["Primera.", "Segunda."])
    }

    func testQueuedAnnouncementDoesNotCancel() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Empezamos la ruta.")
        let stopsBefore = synthesizer.stopCount
        voice.announce("Gira a la derecha.", interrupt: false)
        XCTAssertEqual(synthesizer.stopCount, stopsBefore)
    }

    func testSameInstructionIsNotRepeatedBackToBack() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Gira a la derecha.")
        voice.announce("Gira a la derecha.")
        XCTAssertEqual(synthesizer.spoken.count, 1)
        voice.announce("Continúa recto.")
        voice.announce("Gira a la derecha.")
        XCTAssertEqual(synthesizer.spoken.count, 3)
    }

    func testStopAllowsTheSameInstructionAgain() {
        let synthesizer = FakeSynthesizer()
        let session = FakeSession()
        let voice = makeVoice(synthesizer: synthesizer, session: session)
        voice.announce("Has llegado a tu destino.")
        voice.stop()
        voice.announce("Has llegado a tu destino.")
        XCTAssertEqual(synthesizer.spoken.count, 2)
        XCTAssertGreaterThanOrEqual(session.deactivateCount, 1)
    }

    // MARK: Sesión de audio

    func testAudioSessionConstants() {
        XCTAssertEqual(NavigationVoice.audioCategory, .playback)
        XCTAssertEqual(NavigationVoice.audioMode, .spokenAudio)
        XCTAssertTrue(NavigationVoice.audioOptions.contains(.duckOthers))
    }

    func testSessionIsConfiguredAtInitAndActivatedWhenSpeaking() {
        let session = FakeSession()
        let voice = makeVoice(session: session)
        XCTAssertEqual(session.configureCount, 1)
        voice.announce("Hola.")
        XCTAssertEqual(session.activateCount, 1)
    }

    func testSystemSessionAppliesPlaybackSpokenAudioDuckOthers() throws {
        do { try SystemAudioSession().configure() } catch { throw XCTSkip("AVAudioSession no disponible en este entorno: \(error)") }
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
    }

    // MARK: Selección de voz

    func testPrefersSpainVoiceOfRequestedGenderAndHigherQuality() {
        let list = [
            voice("a", lang: "es-MX", quality: 3, gender: .girl),
            voice("b", lang: "es-ES", quality: 1, gender: .girl),
            voice("c", lang: "es-ES", quality: 2, gender: .girl),
            voice("d", lang: "es-ES", quality: 3, gender: .boy),
        ]
        let girl = VoiceSelector.select(from: list, gender: .girl)
        XCTAssertEqual(girl.voice?.identifier, "c")
        XCTAssertEqual(girl.match, .exact)
        let boy = VoiceSelector.select(from: list, gender: .boy)
        XCTAssertEqual(boy.voice?.identifier, "d")
    }

    func testFallsBackToOtherGenderInSpainAndWarns() {
        let list = [voice("g", gender: .girl)]
        let boy = VoiceSelector.select(from: list, gender: .boy)
        XCTAssertEqual(boy.voice?.identifier, "g")
        XCTAssertEqual(boy.match, .fallbackSpain)

        let voiceService = makeVoice(voices: list)
        voiceService.gender = .boy
        XCTAssertNotNil(voiceService.warning)
        XCTAssertTrue(voiceService.warning?.contains("chico") ?? false)
    }

    func testUsesOtherSpanishRegionBeforeNothing() {
        let list = [voice("mx", lang: "es-MX", gender: .boy)]
        XCTAssertEqual(VoiceSelector.select(from: list, gender: .boy).match, .exactOutsideSpain)
        XCTAssertEqual(VoiceSelector.select(from: [voice("ar", lang: "es-AR", gender: .girl)], gender: .boy).match, .fallbackSpanish)
    }

    func testNoSpanishVoiceInstalled() {
        let english = [voice("en", lang: "en-US", gender: .girl)]
        let selection = VoiceSelector.select(from: english, gender: .girl)
        XCTAssertNil(selection.voice)
        XCTAssertEqual(selection.match, .noSpanishVoice)
        let service = makeVoice(voices: english)
        XCTAssertNotNil(service.warning)
        XCTAssertEqual(service.statusText, "Voz actual: predeterminada del sistema")
    }

    func testStatusTextForExactMatchHasNoWarning() {
        let service = makeVoice(voices: [voice("m", name: "Mónica", gender: .girl)])
        XCTAssertEqual(service.statusText, "Voz actual: española — chica (Mónica)")
        XCTAssertNil(service.warning)
    }

    func testGenderFromNameFallback() {
        XCTAssertEqual(VoiceInfo.genderFromName("Mónica"), .girl)
        XCTAssertEqual(VoiceInfo.genderFromName("Jorge"), .boy)
        XCTAssertNil(VoiceInfo.genderFromName("Desconocida"))
    }
}
