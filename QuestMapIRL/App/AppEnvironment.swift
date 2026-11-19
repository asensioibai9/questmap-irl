import CoreLocation
import Foundation
import SwiftData

/// Composición de dependencias. Cada servicio es independiente del renderizador del mapa y se
/// puede sustituir (proveedor de rutas, de búsqueda, de ubicación) sin tocar la interfaz.
@MainActor
final class AppEnvironment {
    /// Instancia de producción compartida entre la escena del iPhone y la de CarPlay.
    static let shared = AppEnvironment()

    let locationService: LocationServiceProtocol
    let routeService: RouteServiceProtocol
    let placeSearch: PlaceSearchProviding
    let nearby: NearbySearchProviding
    let speech: SpeechService
    let network: NetworkMonitor
    let speedLimits: SpeedLimitProviding
    let music: MusicPlayerModel
    /// Navegación activa compartida por el iPhone y CarPlay.
    let hub: NavigationHub

    /// Servicios reales de producción.
    init() {
        let location = LocationService()
        let routes = OSRMRouteService()
        let speech = SpeechService()
        let limits = ValhallaSpeedLimitService()
        self.locationService = location
        self.routeService = routes
        self.placeSearch = PhotonSearchService()
        self.nearby = TilePOISearchService()
        self.speech = speech
        self.network = NetworkMonitor()
        self.speedLimits = limits
        self.music = MusicPlayerModel(backends: [AppleMusicBackend(), SpotifyMusicBackend.makeDefault(), SystemNowPlayingBackend()])
        // Voz grabada activa: se consulta en cada indicación (cambiar o borrar el perfil se aplica a la siguiente).
        speech.recordedVoice = {
            PerformanceTrace.measure("voice-profile-resolve", thresholdMs: 30) {
                AppEnvironment.activeRecordedVoice(context: ContainerFactory.shared.mainContext)
            }
        }
        let freeDrive = FreeDriveSpeedLimit(matcher: limits)
        // Casa y Trabajo: alrededor de ellos no se envía ningún punto del recorrido (se leen aquí, no se registran).
        freeDrive.excludedAreas = {
            let personal: Set<String> = [PlaceKind.home.rawValue, PlaceKind.work.rawValue]
            do {
                return try ContainerFactory.shared.mainContext.fetch(FetchDescriptor<SavedPlace>())
                    .filter { personal.contains($0.kindRawValue) }
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            } catch {
                // Sin poder leerlos no se sabe dónde están: nil = por prudencia, el modo sin ruta no envía nada.
                return nil
            }
        }
        self.hub = NavigationHub(
            location: location, routeService: routes, speech: speech, speedLimits: limits, freeDrive: freeDrive,
            settings: {
                let stored = try? ContainerFactory.shared.mainContext.fetch(FetchDescriptor<UserSettings>()).first
                return (stored?.useMetricUnits ?? true, stored?.showSpeedLimit ?? true)
            },
            tripStore: { summary in
                try? TripRepository(context: ContainerFactory.shared.mainContext).save(summary)
            })
    }

    /// Perfil de voz activo listo para sonar, o nil (voz del sistema) si no hay, se borró o no se puede leer.
    /// Un perfil INCOMPLETO nunca deja sin voz lo esencial: aunque se eligiera «solo grabaciones», lo que falte se dice
    /// con la voz del sistema hasta que estén todas las obligatorias.
    static func activeRecordedVoice(context: ModelContext, files: VoiceRecordingFiles = .standard,
                                    packs: GeneratedVoicePackLoader? = nil) -> RecordedVoiceSource? {
        let packs = packs ?? .shared
        let settings: UserSettings?
        do {
            settings = try context.fetch(FetchDescriptor<UserSettings>()).first
        } catch {
            return nil
        }
        guard let settings else { return nil }
        // Paquete generado incluido en la app: solo si está COMPLETO; si no, voz del sistema (nunca a medias en silencio).
        if let packID = settings.activeGeneratedVoicePackID {
            guard let pack = packs.pack(id: packID), pack.availability.isReady else { return nil }
            return RecordedVoiceSource(segments: pack.segments, strategy: settings.voiceFallback, fallbackOnFailure: true)
        }
        guard let id = settings.activeVoiceProfileID else { return nil }
        let store = VoiceProfileStore(context: context, files: files)
        guard let profile = store.profile(id: id) else { return nil }
        let segments = store.segments(for: id)
        guard !segments.isEmpty else { return nil }
        var strategy = settings.voiceFallback
        let progress = VoiceProfileProgress.make(recorded: Set(segments.keys), language: profile.languageCode)
        if strategy == .recordingsOnly && !progress.isReady { strategy = .hybrid }
        return RecordedVoiceSource(segments: segments, strategy: strategy)
    }

    /// Inyección explícita para previews y tests.
    init(locationService: LocationServiceProtocol,
         routeService: RouteServiceProtocol,
         placeSearch: PlaceSearchProviding,
         nearby: NearbySearchProviding,
         speech: SpeechService,
         network: NetworkMonitor,
         speedLimits: SpeedLimitProviding = ValhallaSpeedLimitService(),
         music: MusicPlayerModel? = nil,
         hub: NavigationHub? = nil) {
        self.locationService = locationService
        self.routeService = routeService
        self.placeSearch = placeSearch
        self.nearby = nearby
        self.speech = speech
        self.network = network
        self.speedLimits = speedLimits
        self.music = music ?? MusicPlayerModel(backend: AppleMusicBackend())
        self.hub = hub ?? NavigationHub(location: locationService, routeService: routeService, speech: speech,
                                        speedLimits: speedLimits)
    }
}
