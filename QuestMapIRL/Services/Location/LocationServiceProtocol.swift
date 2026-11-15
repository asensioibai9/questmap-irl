import CoreLocation
import Observation

enum LocationAuthState: Equatable {
    case notDetermined
    case denied
    case authorizedWhenInUse
    case authorizedAlways
}

/// Contrato del servicio de ubicación. La UI solo conoce este protocolo.
@MainActor
protocol LocationServiceProtocol: AnyObject {
    var authState: LocationAuthState { get }
    var currentLocation: CLLocation? { get }
    var heading: CLHeading? { get }

    func requestWhenInUseAuthorization()
    func startUpdating()
    func stopUpdating()
}
