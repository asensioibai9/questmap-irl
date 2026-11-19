import CoreLocation
import UIKit
import Observation

enum LocationAuthState: Equatable {
    case notDetermined
    case denied
    case restricted
    case servicesDisabled
    case authorizedWhenInUse
    case authorizedAlways

    var isAuthorized: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}

/// Calidad de la señal GPS a partir de la precisión horizontal y la antigüedad del último fix.
enum GPSQuality: Equatable {
    case none, poor, fair, good, excellent

    var title: String {
        switch self {
        case .none: return "Sin señal"
        case .poor: return "Mala"
        case .fair: return "Regular"
        case .good: return "Buena"
        case .excellent: return "Excelente"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "location.slash"
        case .poor: return "dot.radiowaves.left.and.right"
        case .fair: return "dot.radiowaves.left.and.right"
        case .good: return "dot.radiowaves.left.and.right"
        case .excellent: return "dot.radiowaves.left.and.right"
        }
    }

    var bars: Int {
        switch self {
        case .none: return 0
        case .poor: return 1
        case .fair: return 2
        case .good: return 3
        case .excellent: return 4
        }
    }
}

enum LocationMode {
    case idle         // mapa abierto: precisión moderada, ahorra batería
    case navigating   // navegación activa: máxima precisión
}

/// Contrato del servicio de ubicación. La UI solo conoce este protocolo.
@MainActor
protocol LocationServiceProtocol: AnyObject {
    var authState: LocationAuthState { get }
    /// Último fix crudo de Core Location.
    var currentLocation: CLLocation? { get }
    /// Posición suavizada para dibujar sin saltos.
    var smoothedLocation: CLLocation? { get }
    /// Rumbo a mostrar: course GPS si hay movimiento, brújula si no (grados 0-360).
    var displayHeading: Double { get }
    /// Valoración basada SOLO en la precisión horizontal de la última lectura (no es un porcentaje de señal).
    var quality: GPSQuality { get }
    /// Estado real de la ubicación (permiso, obteniendo, disponible, impreciso, sin confirmar…).
    var status: LocationStatus { get }
    var accuracyMode: LocationAccuracyMode { get }
    /// true solo cuando la última lectura es antigua y NO se ha podido confirmar (ver `LocationStatusEvaluator`).
    var isSignalLost: Bool { get }
    /// Resumen sin coordenadas para el informe de diagnóstico.
    var diagnosticSummary: String { get }

    func requestWhenInUseAuthorization()
    func start(mode: LocationMode)
    func setMode(_ mode: LocationMode)
    func stop()
    /// Pide una lectura nueva (o el permiso si falta) y reanuda las actualizaciones si estaban paradas.
    func refreshNow()
    /// Solicita ubicación precisa temporal cuando el usuario solo concedió la aproximada.
    func requestTemporaryFullAccuracy()
    /// La interfaz cambió de orientación (vertical / horizontal a un lado u otro): referencia de la brújula.
    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation)
}

extension LocationServiceProtocol {
    /// Implementaciones sin brújula (pruebas): no hacen nada.
    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {}
}
