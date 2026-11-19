import CoreLocation
import MapLibre
import UIKit

enum FollowMode: Equatable {
    case off
    case northUp
    case headingUp
}

/// Controlador del renderizador cartográfico. Guarda el estado de las capas de navegación (ruta,
/// destino, usuario) y lo vuelve a aplicar tras cada carga de estilo, de modo que cambiar de
/// estilo conserva ruta, destino, posición y cámara sin duplicar nada: las fuentes viven en el
/// propio JSON del estilo y aquí solo se actualiza su contenido.
///
/// Debe usarse siempre desde el hilo principal.
final class MapController {
    private weak var mapView: MLNMapView?
    private var styleReady = false

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var destination: CLLocationCoordinate2D?
    /// Movimiento visual de la flecha (posición presentada ≠ lectura real). Ver `MarkerMotion`.
    private var motion = MarkerMotion()
    private let smoother = FollowCameraSmoother()
    /// Estado de la cámara mientras se sigue al usuario (nil = leerlo del mapa en el siguiente fotograma).
    private var cameraState: FollowCameraSmoother.State?
    /// Vuelo animado de MapLibre en curso (recentrado desde lejos): mientras dura no se toca la cámara por fotograma.
    private var flightActive = false
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval?
    private var lastPushedUser: (coordinate: CLLocationCoordinate2D, heading: Double)?
    private var appliedInset: UIEdgeInsets?
    private var markers: [Place] = []
    private var selection: CLLocationCoordinate2D?
    private var savedMarkers: [(coordinate: CLLocationCoordinate2D, icon: String)] = []
    private var avatar: MapAvatar = .arrow
    private var arrowColorHex: UInt32 = 0xFFFFFF
    private var arrowBadgeHex: UInt32?

    private(set) var followMode: FollowMode = .northUp
    private var followZoom: Double = 15.5
    private var followPitch: Double = 0
    private var buildings3D = false
    private var simplified = false
    /// Capas elegidas en «Capas del mapa». nil = la pantalla no las gestiona (CarPlay): se usa lo que trae el estilo.
    private var layerPreferences: MapLayerPreferences?
    private var showPlaceNames = true
    /// Nombre original de cada capa de iconos (para restaurarlo al volver a activar los nombres).
    private var originalPOIText: [String: NSExpression] = [:]
    /// Márgenes de la cámara de seguimiento: el usuario se coloca en el centro del área que dejan libre los paneles.
    private var followInsets: UIEdgeInsets = .zero
    /// Ruta encuadrada entera (vista previa o «ver ruta completa») mientras el usuario no mueva el mapa.
    private var wholeRoute: [CLLocationCoordinate2D]?
    private var hasCenteredOnUser = false

    /// Se llama cuando el usuario mueve el mapa con un gesto y se deja de seguirle.
    var onFollowCancelled: (() -> Void)?

    // MARK: - Ciclo de vida del mapa

    func attach(_ view: MLNMapView) {
        mapView = view
        styleReady = false
        cameraState = nil
        flightActive = false
        appliedInset = nil
        if let shown = motion.displayed {
            view.setCenter(shown, zoomLevel: followZoom, animated: false)
        }
        startDisplayLinkIfNeeded()
    }

    func detach(_ view: MLNMapView) {
        guard mapView === view else { return }
        mapView = nil
        styleReady = false
        cameraState = nil
        stopDisplayLink()
    }

    func styleDidLoad(_ style: MLNStyle, arrowHex: UInt32, badgeHex: UInt32? = nil) {
        styleReady = true
        arrowColorHex = arrowHex
        arrowBadgeHex = badgeHex
        UserArrowImage.register(in: style, avatar: avatar, arrowHex: arrowHex, badgeHex: badgeHex)
        pushRoute()
        pushDestination()
        pushMarkers()
        pushSelection(animated: false)
        pushSaved()
        lastPushedUser = nil                          // fuente nueva del estilo: hay que volver a rellenarla
        pushUser()
        applyBuildings()
        originalPOIText = [:]                         // capas nuevas del estilo recién cargado
        applyLayerVisibility()
        applyPlaceNames()
        applyPitch(animated: false)
        cameraState = nil
        startDisplayLinkIfNeeded()
    }

    /// Cambia el avatar de la posición del usuario sin recargar el mapa.
    func setAvatar(_ newAvatar: MapAvatar) {
        guard newAvatar != avatar else { return }
        avatar = newAvatar
        guard styleReady, let style = mapView?.style else { return }
        UserArrowImage.register(in: style, avatar: avatar, arrowHex: arrowColorHex, badgeHex: arrowBadgeHex)
    }

    /// Marcadores de resultados de búsqueda (categorías, lugares guardados mostrados en el mapa).
    func setMarkers(_ places: [Place]) {
        markers = places
        pushMarkers()
    }

    /// Punto seleccionado (cuatro flechas alrededor). Solo hay una selección: la nueva sustituye a la anterior;
    /// nil la quita. Las flechas siguen ancladas a la coordenada al mover, rotar o ampliar el mapa.
    func setSelection(_ coordinate: CLLocationCoordinate2D?) {
        let changed = selection?.latitude != coordinate?.latitude || selection?.longitude != coordinate?.longitude
        selection = coordinate
        pushSelection(animated: changed && coordinate != nil)
    }

    /// Casa y Trabajo guardados, dibujados con sus iconos.
    func setSavedPlaces(_ places: [(coordinate: CLLocationCoordinate2D, icon: String)]) {
        savedMarkers = places
        pushSaved()
    }

    /// Mapa para la pantalla de un coche: oculta iconos de puntos de interés, números de portal y marcadores de resultados
    /// (la ruta, el destino y la posición del usuario se conservan). Se vuelve a aplicar tras cada carga de estilo.
    func setSimplified(_ enabled: Bool) {
        simplified = enabled
        applyLayerVisibility()
    }

    /// Capas activadas en «Capas del mapa». Solo cambia la VISIBILIDAD de capas que ya están en el estilo: no se
    /// recarga el estilo, no se mueve la cámara, no se toca la ruta ni la ubicación. Se vuelve a aplicar tras cambiar
    /// de estilo. Resultados de búsqueda, destino, selección y Casa/Trabajo son capas aparte y siguen visibles siempre.
    func setMapLayers(_ preferences: MapLayerPreferences) {
        guard preferences != layerPreferences else { return }
        layerPreferences = preferences
        applyLayerVisibility()
    }

    /// Nombres breves bajo los iconos de lugares (sin tocar los iconos). Se aplica al momento y tras cambiar de estilo.
    func setPlaceNames(_ show: Bool) {
        guard show != showPlaceNames else { return }
        showPlaceNames = show
        applyPlaceNames()
    }

    /// Edificios 3D encendidos/apagados. Solo cambia la visibilidad de la capa `building-3d` (que ya está en el
    /// estilo): no se reconstruye ni se recarga nada. Se vuelve a aplicar tras cada carga de estilo.
    func setBuildings3D(_ enabled: Bool) {
        buildings3D = enabled
        applyBuildings()
    }

    /// Inclinación de la cámara (0 = cenital). Transición suave; conserva centro, zoom y rumbo, y por tanto
    /// ruta, destino y marcadores. Se recuerda para aplicarla también tras cambiar de estilo.
    func setPerspective(_ pitch: Double, animated: Bool = true) {
        followPitch = pitch
        applyPitch(animated: animated)
    }

    /// Centra el mapa en un punto sin seguir al usuario.
    func focus(on coordinate: CLLocationCoordinate2D, zoom: Double = 16, bottomInset: CGFloat = 0) {
        followMode = .off
        cameraState = nil
        wholeRoute = nil
        onFollowCancelled?()
        guard let mapView else { return }
        setInset(UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0), on: mapView)
        mapView.setCenter(coordinate, zoomLevel: zoom, direction: 0, animated: true)
    }

    /// Gesto del usuario sobre el mapa: se deja de seguir al momento (no se lucha contra el gesto). La flecha sigue
    /// moviéndose; la cámara ya no. Se reanuda con el botón de recentrar (`setFollow`).
    func userMovedCamera() {
        wholeRoute = nil                              // ya no es «la ruta entera»: al girar no se vuelve a encuadrar
        guard followMode != .off else { return }
        followMode = .off
        cameraState = nil
        onFollowCancelled?()
    }

    // MARK: - Capas de navegación

    func setRoute(_ coordinates: [CLLocationCoordinate2D]) {
        routeCoordinates = coordinates
        pushRoute()
    }

    func setDestination(_ coordinate: CLLocationCoordinate2D?) {
        destination = coordinate
        pushDestination()
    }

    /// Lectura nueva del servicio de ubicación y rumbo elegido. La flecha va de su posición presentada actual a esta
    /// lectura con una transición continua (`MarkerMotion`); nunca pasa de la última lectura recibida. Llamarla solo
    /// por un cambio de rumbo (misma lectura) no reinicia el movimiento.
    func setUser(_ fix: CLLocation, heading: Double) {
        let now = CACurrentMediaTime()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let first = motion.displayed == nil
        motion.receive(coordinate: fix.coordinate, timestamp: fix.timestamp, speed: fix.speed,
                       accuracy: fix.horizontalAccuracy, now: now, reduceMotion: reduceMotion)
        motion.receive(heading: heading, reduceMotion: reduceMotion)
        if first || reduceMotion {
            motion.step(now: now)
            pushUser()
        }
        if !hasCenteredOnUser, followMode != .off, let mapView, let shown = motion.displayed {
            // Primera posición: se centra directamente (sin cruzar el mundo desde la vista inicial).
            setInset(followInsets, on: mapView)
            mapView.setCenter(shown, zoomLevel: followZoom,
                              direction: followMode == .headingUp ? motion.displayedHeading : 0, animated: false)
            hasCenteredOnUser = true
            cameraState = nil
        }
        startDisplayLinkIfNeeded()
    }

    // MARK: - Cámara

    /// Activa (o cambia) el seguimiento. La cámara llega al objetivo con la misma aproximación suave que usa cada
    /// fotograma; si el usuario estaba lejos (había movido el mapa), primero un vuelo corto de MapLibre.
    func setFollow(_ mode: FollowMode, zoom: Double, pitch: Double, bottomInset: CGFloat) {
        setFollow(mode, zoom: zoom, pitch: pitch, insets: UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0))
    }

    /// Igual, con márgenes en los cuatro lados (en horizontal el panel de navegación va a un lado).
    func setFollow(_ mode: FollowMode, zoom: Double, pitch: Double, insets: UIEdgeInsets) {
        followMode = mode
        followZoom = zoom
        followPitch = pitch
        followInsets = insets
        wholeRoute = nil
        cameraState = nil
        guard let mapView else { return }
        guard mode != .off else { return }
        setInset(insets, on: mapView)
        if let shown = motion.displayed, !UIAccessibility.isReduceMotionEnabled, isFar(shown, zoom: zoom, in: mapView) {
            flightActive = true
            mapView.setCenter(shown, zoomLevel: zoom, direction: mode == .headingUp ? motion.displayedHeading : 0,
                              animated: true) { [weak self] in
                self?.flightActive = false
                self?.cameraState = nil
                self?.startDisplayLinkIfNeeded()
            }
        }
        hasCenteredOnUser = hasCenteredOnUser || motion.displayed != nil
        startDisplayLinkIfNeeded()
    }

    /// true si el punto queda fuera de la pantalla (con margen) o el zoom cambia mucho: mejor un vuelo que un deslizamiento.
    private func isFar(_ coordinate: CLLocationCoordinate2D, zoom: Double, in mapView: MLNMapView) -> Bool {
        if abs(mapView.zoomLevel - zoom) > 2 { return true }
        let point = mapView.convert(coordinate, toPointTo: mapView)
        return !mapView.bounds.insetBy(dx: -mapView.bounds.width * 0.5, dy: -mapView.bounds.height * 0.5).contains(point)
    }

    /// La superficie libre cambió (giro del iPhone, panel que aparece): nuevos márgenes SIN tocar el modo, el zoom, la
    /// inclinación ni el rumbo. Si se sigue al usuario, la cámara se desliza hacia el nuevo centro con el mismo suavizado
    /// de siempre; si el usuario está explorando a mano, no se mueve nada.
    func updateFollowInsets(_ insets: UIEdgeInsets) {
        followInsets = insets
        guard followMode != .off, let mapView else { return }
        setInset(insets, on: mapView)
        cameraState = nil
        startDisplayLinkIfNeeded()
    }

    /// Vuelve a encuadrar la ruta entera en la superficie nueva, solo si se estaba viendo entera y el usuario no ha movido
    /// el mapa desde entonces. Devuelve si lo ha hecho.
    @discardableResult
    func refitWholeRoute(insets: UIEdgeInsets) -> Bool {
        guard followMode == .off, let coordinates = wholeRoute else { return false }
        fit(coordinates, insets: insets)
        return true
    }

    private func setInset(_ inset: UIEdgeInsets, on mapView: MLNMapView) {
        guard appliedInset != inset else { return }
        appliedInset = inset
        mapView.contentInset = inset
    }

    /// Encuadra una ruta completa (vista previa).
    func fit(_ coordinates: [CLLocationCoordinate2D], insets: UIEdgeInsets) {
        followMode = .off
        cameraState = nil
        guard let mapView, !coordinates.isEmpty else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        wholeRoute = coordinates
        setInset(.zero, on: mapView)
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        )
        mapView.setDirection(0, animated: false)
        mapView.setVisibleCoordinateBounds(bounds, edgePadding: insets, animated: true)
    }

    // MARK: - Privado

    /// Visibilidad de las capas gestionables. CarPlay (simplificado) oculta iconos, portales, cimas, resultados y lugares
    /// guardados por encima de cualquier preferencia.
    private func applyLayerVisibility() {
        guard styleReady, let style = mapView?.style else { return }
        let managed = layerPreferences?.styleLayerVisibility ?? [:]
        for layer in style.layers {
            let id = layer.identifier
            let hiddenInCar = id.hasPrefix("poi-icon") || id == "label-housenumber" || id == "label-peak"
                || id.hasPrefix("results-") || id == "saved-places"
            let target: Bool?
            if hiddenInCar && simplified {
                target = false
            } else if let preference = managed[id] {
                target = preference
            } else if hiddenInCar {
                target = true
            } else {
                target = nil                       // capa no gestionada: como venga en el estilo
            }
            if let target, layer.isVisible != target { layer.isVisible = target }
        }
    }

    private func applyPlaceNames() {
        guard styleReady, let style = mapView?.style else { return }
        for layer in style.layers where layer.identifier.hasPrefix("poi-icon") {
            guard let symbols = layer as? MLNSymbolStyleLayer else { continue }
            if originalPOIText[layer.identifier] == nil, let text = symbols.text { originalPOIText[layer.identifier] = text }
            if showPlaceNames {
                if let original = originalPOIText[layer.identifier] { symbols.text = original }
            } else {
                symbols.text = NSExpression(forConstantValue: "")
            }
        }
    }

    private func applyBuildings() {
        guard styleReady, let layer = mapView?.style?.layer(withIdentifier: "building-3d") else { return }
        layer.isVisible = buildings3D
    }

    private func applyPitch(animated: Bool) {
        guard let mapView, styleReady else { return }
        // Siguiendo al usuario, la inclinación la lleva la cámara por fotograma (una sola fuente de movimiento).
        if followMode != .off, motion.displayed != nil {
            startDisplayLinkIfNeeded()
            return
        }
        let camera = mapView.camera
        guard abs(Double(camera.pitch) - followPitch) > 0.5 else { return }
        camera.pitch = CGFloat(followPitch)
        let duration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.6 : 0
        mapView.setCamera(camera, withDuration: duration, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    // MARK: - Bucle de animación (solo mientras hay algo que mover)

    /// CADisplayLink sincronizado con el refresco de pantalla. Se crea solo cuando la flecha o la cámara tienen que
    /// moverse y se para en cuanto llegan a su objetivo: con el usuario quieto no hay ningún temporizador activo.
    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, mapView != nil, needsFrames else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrameTime = nil
        motion.resetClock()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = nil
    }

    private var needsFrames: Bool {
        if motion.isAnimating { return true }
        guard followMode != .off, !flightActive, mapView != nil, motion.displayed != nil else { return false }
        guard let cameraState else { return true }
        return !smoother.converged(cameraState, followTarget())
    }

    fileprivate func frame(at now: CFTimeInterval) {
        guard mapView != nil else { stopDisplayLink(); return }
        let dt = lastFrameTime.map { min(0.1, max(0, now - $0)) } ?? (1.0 / 60)
        lastFrameTime = now
        motion.step(now: now)
        pushUser()
        updateCamera(dt: dt)
        if !needsFrames { stopDisplayLink() }
    }

    private func followTarget() -> FollowCameraSmoother.State {
        FollowCameraSmoother.State(center: motion.displayed ?? CLLocationCoordinate2D(),
                                   zoom: followZoom, pitch: followPitch,
                                   direction: followMode == .headingUp ? motion.displayedHeading : 0)
    }

    /// Mueve la cámara un fotograma hacia la flecha PRESENTADA (no hacia la lectura cruda), sin animaciones de MapLibre:
    /// así cámara y flecha avanzan juntas y nada compite.
    private func updateCamera(dt: Double) {
        guard followMode != .off, !flightActive, let mapView, motion.displayed != nil else { return }
        let current = cameraState ?? FollowCameraSmoother.State(center: mapView.centerCoordinate, zoom: mapView.zoomLevel,
                                                                pitch: Double(mapView.camera.pitch),
                                                                direction: HeadingMath.normalized(mapView.direction))
        let next = smoother.step(current, toward: followTarget(), dt: dt, immediate: UIAccessibility.isReduceMotionEnabled)
        if cameraState == nil || next != current {
            if abs(Double(mapView.camera.pitch) - next.pitch) > 0.01 {
                let camera = mapView.camera
                camera.pitch = CGFloat(next.pitch)
                mapView.setCamera(camera, animated: false)
            }
            mapView.setCenter(next.center, zoomLevel: next.zoom, direction: next.direction, animated: false)
        }
        cameraState = next
    }

    private func shapeSource(_ identifier: String) -> MLNShapeSource? {
        guard styleReady, let style = mapView?.style else { return nil }
        return style.source(withIdentifier: identifier) as? MLNShapeSource
    }

    private func pushRoute() {
        guard let source = shapeSource("route") else { return }
        if routeCoordinates.count >= 2 {
            let coordinates = routeCoordinates
            source.shape = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
        } else {
            source.shape = nil
        }
    }

    private func pushDestination() {
        guard let source = shapeSource("destination") else { return }
        if let destination {
            let feature = MLNPointFeature()
            feature.coordinate = destination
            source.shape = feature
        } else {
            source.shape = nil
        }
    }

    private func pushSelection(animated: Bool) {
        guard let source = shapeSource("selection") else { return }
        guard let selection else {
            source.shape = nil
            return
        }
        let feature = MLNPointFeature()
        feature.coordinate = selection
        source.shape = feature
        // Aparición breve y suave (sin parpadeo continuo); con "Reducir movimiento" aparece directamente.
        guard animated, !UIAccessibility.isReduceMotionEnabled,
              let layer = mapView?.style?.layer(withIdentifier: "selection-arrows") as? MLNSymbolStyleLayer else { return }
        layer.iconOpacityTransition = MLNTransition(duration: 0.22, delay: 0)
        layer.iconOpacity = NSExpression(forConstantValue: 0)
        DispatchQueue.main.async { layer.iconOpacity = NSExpression(forConstantValue: 1) }
    }

    private func pushSaved() {
        guard let source = shapeSource("saved") else { return }
        if savedMarkers.isEmpty {
            source.shape = nil
            return
        }
        let features: [MLNPointFeature] = savedMarkers.map { item in
            let feature = MLNPointFeature()
            feature.coordinate = item.coordinate
            feature.attributes = ["icon": item.icon]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func pushMarkers() {
        guard let source = shapeSource("results") else { return }
        if markers.isEmpty {
            source.shape = nil
            return
        }
        let features: [MLNPointFeature] = markers.map { place in
            let feature = MLNPointFeature()
            feature.coordinate = place.coordinate
            feature.attributes = ["name": place.name]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func pushUser() {
        // Se conserva la misma fuente y capa: solo cambia el punto y su atributo de rumbo (no se recrea nada), y solo si
        // de verdad cambió desde el último fotograma.
        guard let source = shapeSource("user") else { return }
        guard let shown = motion.displayed else {
            if lastPushedUser != nil { source.shape = nil }
            lastPushedUser = nil
            return
        }
        let heading = motion.displayedHeading
        if let last = lastPushedUser, MarkerMotion.same(last.coordinate, shown), abs(last.heading - heading) < 0.01 { return }
        let feature = MLNPointFeature()
        feature.coordinate = shown
        feature.attributes = ["heading": heading]
        source.shape = feature
        lastPushedUser = (shown, heading)
    }
}

/// CADisplayLink retiene su objetivo: este intermediario débil evita que retenga al controlador.
private final class DisplayLinkProxy: NSObject {
    private weak var owner: MapController?
    init(_ owner: MapController) { self.owner = owner }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.frame(at: link.timestamp)
    }
}
