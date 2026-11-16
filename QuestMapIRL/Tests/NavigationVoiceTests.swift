import XCTest
import AVFoundation
@testable import QuestMapIRL

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

    func testVolumeAndGenderPersistBetweenLaunches() {
        let first = makeVoice()
        first.gender = .boy
        first.volume = 0.6
        let second = makeVoice()
        XCTAssertEqual(second.gender, .boy)
        XCTAssertEqual(second.volume, 0.6, accuracy: 0.0001)
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

    // MARK: Frase y parámetros

    func testTestPhraseIsSpokenWithExpectedParameters() throws {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.playTest()

        XCTAssertEqual(NavigationVoice.testPhrase, "Prueba de voz. En doscientos metros, gira a la derecha.")
        let utterance = try XCTUnwrap(synthesizer.spoken.first)
        XCTAssertEqual(utterance.speechString, NavigationVoice.testPhrase)
        XCTAssertEqual(utterance.rate, 0.48, accuracy: 0.0001)
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

    // MARK: Estado "Reproduciendo…"

    func testPlayingStateStartsAndEndsWithTheTestUtterance() throws {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        XCTAssertFalse(voice.isPlayingTest)
        voice.playTest()
        XCTAssertTrue(voice.isPlayingTest)
        voice.utteranceEnded(try XCTUnwrap(synthesizer.spoken.last))
        XCTAssertFalse(voice.isPlayingTest)
    }

    func testToggleTestStopsWhilePlaying() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.toggleTest()
        XCTAssertTrue(voice.isPlayingTest)
        voice.toggleTest()
        XCTAssertFalse(voice.isPlayingTest)
        XCTAssertGreaterThanOrEqual(synthesizer.stopCount, 2)
    }

    func testStopTestIfPlayingDoesNotTouchNavigationVoiceWhenIdle() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Gira a la derecha.")
        let stops = synthesizer.stopCount
        voice.stopTestIfPlaying()
        XCTAssertEqual(synthesizer.stopCount, stops)
    }

    // MARK: Cancelación, repetición y parada

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
        XCTAssertEqual(synthesizer.spoken.count, 2)
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

    func testStopImmediatelyStopsSpeechAndReleasesAudio() {
        let synthesizer = FakeSynthesizer()
        let session = FakeSession()
        let voice = makeVoice(synthesizer: synthesizer, session: session)
        voice.playTest()
        let stopsBefore = synthesizer.stopCount
        voice.stopImmediately()
        XCTAssertEqual(synthesizer.stopCount, stopsBefore + 1)
        XCTAssertFalse(voice.isPlayingTest)
        XCTAssertEqual(session.deactivateCount, 1)
    }

    func testStopAllowsTheSameInstructionAgain() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Has llegado a tu destino.")
        voice.stopImmediately()
        voice.announce("Has llegado a tu destino.")
        XCTAssertEqual(synthesizer.spoken.count, 2)
    }

    func testLateCancellationOfADiscardedPhraseDoesNotReleaseTheNewOne() throws {
        let synthesizer = FakeSynthesizer()
        let session = FakeSession()
        let voice = makeVoice(synthesizer: synthesizer, session: session)
        voice.announce("Primera.")
        let first = try XCTUnwrap(synthesizer.spoken.last)
        voice.announce("Segunda.")
        let second = try XCTUnwrap(synthesizer.spoken.last)

        // iOS avisa tarde de que la primera se canceló: la segunda sigue sonando y la sesión sigue activa.
        voice.utteranceEnded(first)
        XCTAssertEqual(session.deactivateCount, 0)
        voice.utteranceEnded(second)
        XCTAssertEqual(session.deactivateCount, 1)
    }

    func testReleaseAfterSpeakingDoesNotCutTheCurrentPhrase() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Has llegado a tu destino.")
        let stops = synthesizer.stopCount
        voice.releaseAfterSpeaking()
        XCTAssertEqual(synthesizer.stopCount, stops)
        voice.announce("Has llegado a tu destino.")      // la ruta siguiente puede repetirla
        XCTAssertEqual(synthesizer.spoken.count, 2)
    }

    func testMuteStopsCurrentSpeech() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(synthesizer: synthesizer)
        voice.announce("Gira a la derecha.")
        let stops = synthesizer.stopCount
        voice.toggleMute()
        XCTAssertTrue(voice.isMuted)
        XCTAssertEqual(synthesizer.stopCount, stops + 1)
    }

    // MARK: Robustez

    func testWatchdogRecoversWhenTheSynthesizerNeverReports() async throws {
        let synthesizer = FakeSynthesizer()          // isSpeaking == false y nunca avisa de que terminó
        let session = FakeSession()
        let voice = makeVoice(synthesizer: synthesizer, session: session)
        voice.watchdogSeconds = { _ in 0.05 }
        voice.playTest()
        XCTAssertTrue(voice.isPlayingTest)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(voice.isPlayingTest)
        XCTAssertEqual(session.deactivateCount, 1)
    }

    func testActivationFailureShowsProblemButStillTriesToSpeak() {
        let synthesizer = FakeSynthesizer()
        let session = FakeSession()
        session.activateFails = true
        let voice = makeVoice(synthesizer: synthesizer, session: session)
        voice.announce("Gira a la derecha.")
        XCTAssertNotNil(voice.audioProblem)
        XCTAssertEqual(synthesizer.spoken.count, 1)

        session.activateFails = false
        voice.announce("Continúa recto.")
        XCTAssertNil(voice.audioProblem)
    }

    func testNoSpanishVoiceInstalledDoesNotFail() {
        let synthesizer = FakeSynthesizer()
        let voice = makeVoice(voices: [], synthesizer: synthesizer)
        voice.announce("Gira a la derecha.")
        voice.playTest()
        XCTAssertEqual(synthesizer.spoken.count, 2)
        XCTAssertEqual(voice.selection.match, .noSpanishVoice)
        XCTAssertEqual(voice.statusText, "Voz actual: predeterminada del sistema")
    }

    // MARK: Sesión de audio

    func testAudioSessionConstants() {
        XCTAssertEqual(NavigationVoice.audioCategory, .playback)
        XCTAssertEqual(NavigationVoice.audioMode, .spokenAudio)
        XCTAssertTrue(NavigationVoice.audioOptions.contains(.duckOthers))
    }

    /// No depende de que el simulador deje modificar la sesión real: comprueba qué se le pide.
    func testSystemSessionRequestsPlaybackSpokenAudioDuckOthers() throws {
        let driver = FakeAudioDriver()
        let session = SystemAudioSession(driver: driver)
        try session.activate()
        XCTAssertEqual(driver.categories, [.playback])
        XCTAssertEqual(driver.modes, [.spokenAudio])
        XCTAssertTrue(driver.options.first?.contains(.duckOthers) ?? false)
        XCTAssertEqual(driver.activations, [true])

        session.deactivate()
        XCTAssertEqual(driver.activations, [true, false])
        XCTAssertTrue(driver.deactivationOptions.first?.contains(.notifyOthersOnDeactivation) ?? false)
    }

    func testSessionIsConfiguredAtInitAndActivatedWhenSpeaking() {
        let session = FakeSession()
        let voice = makeVoice(session: session)
        XCTAssertEqual(session.configureCount, 1)
        voice.announce("Hola.")
        XCTAssertEqual(session.activateCount, 1)
    }

    /// Prueba con la sesión REAL del simulador. Puede saltarse si el entorno no la admite; la
    /// lógica ya queda cubierta por `testSystemSessionRequestsPlaybackSpokenAudioDuckOthers`.
    func testRealSessionAppliesPlaybackSpokenAudioDuckOthers() throws {
        do { try SystemAudioSession().configure() } catch { throw XCTSkip("AVAudioSession real no disponible: \(error)") }
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .spokenAudio)
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
    }

    // MARK: Selección de voz y avisos

    func testPrefersSpainVoiceOfRequestedGenderAndHigherQuality() {
        let list = [
            testVoice("a", lang: "es-MX", quality: 3, gender: .girl),
            testVoice("b", lang: "es-ES", quality: 1, gender: .girl),
            testVoice("c", lang: "es-ES", quality: 2, gender: .girl),
            testVoice("d", lang: "es-ES", quality: 3, gender: .boy),
        ]
        let girl = VoiceSelector.select(from: list, gender: .girl)
        XCTAssertEqual(girl.voice?.identifier, "c")
        XCTAssertEqual(girl.match, .exact)
        XCTAssertEqual(VoiceSelector.select(from: list, gender: .boy).voice?.identifier, "d")
    }

    func testWarningWhenThereIsNoVoiceOfTheChosenGender() {
        let service = makeVoice(voices: [testVoice("g", gender: .girl)])
        XCTAssertNil(service.warning)                      // chica: coincide
        service.gender = .boy
        XCTAssertEqual(service.selection.match, .fallbackSpain)
        XCTAssertEqual(service.warning,
                       "No hay una voz de chico en español instalada. Se está usando la mejor voz española disponible.")
    }

    func testWarningWhenOnlyAnotherSpanishRegionMatchesTheGender() {
        let service = makeVoice(voices: [testVoice("mx", lang: "es-MX", gender: .boy)])
        service.gender = .boy
        XCTAssertEqual(service.selection.match, .exactOutsideSpain)
        XCTAssertEqual(service.warning,
                       "No hay una voz de chico de España instalada. Se está usando una voz de chico de otra variante del español.")
    }

    func testWarningWhenNoSpanishVoiceAtAll() {
        let service = makeVoice(voices: [testVoice("en", lang: "en-US", gender: .girl)])
        XCTAssertEqual(service.warning,
                       "No hay ninguna voz en español instalada. Se está usando la voz predeterminada del sistema, que puede leer mal las indicaciones.")
        XCTAssertTrue(NavigationVoice.downloadHint.contains("Contenido hablado"))
    }

    func testFallsBackToOtherSpanishRegions() {
        XCTAssertEqual(VoiceSelector.select(from: [testVoice("ar", lang: "es-AR", gender: .girl)], gender: .boy).match, .fallbackSpanish)
    }

    func testStatusTextForExactMatchHasNoWarning() {
        let service = makeVoice(voices: [testVoice("m", name: "Mónica", gender: .girl)])
        XCTAssertEqual(service.statusText, "Voz actual: española — chica (Mónica)")
        XCTAssertNil(service.warning)
    }

    func testGenderFromNameFallback() {
        XCTAssertEqual(VoiceInfo.genderFromName("Mónica"), .girl)
        XCTAssertEqual(VoiceInfo.genderFromName("Jorge"), .boy)
        XCTAssertNil(VoiceInfo.genderFromName("Desconocida"))
    }
}
