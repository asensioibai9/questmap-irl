import CoreLocation
import UIKit

/// Qué borde del iPhone usa la brújula como «delante», según la orientación de la INTERFAZ.
///
/// Conceptos distintos que no se mezclan en la app:
/// - Orientación de la interfaz: cómo está dibujada la pantalla (vertical, horizontal izquierda/derecha).
/// - Orientación física del dispositivo: cómo se sujeta (puede estar plano, boca arriba…). No se usa para el rumbo.
/// - Rumbo de brújula (`CLHeading`): hacia dónde apunta el borde de referencia del iPhone. Solo se usa PARADO.
/// - Dirección de desplazamiento (`CLLocation.course`): hacia dónde se mueve el GPS. Manda EN MARCHA.
/// - Bearing de la cámara: giro del mapa (rumbo arriba = rumbo mostrado; norte arriba = 0; manual = el del usuario).
/// - Rotación del icono: el rumbo mostrado respecto al MAPA (`icon-rotation-alignment: map`), así que en pantalla la flecha
///   apunta a (rumbo − bearing): arriba en «rumbo arriba» y su dirección geográfica real con norte arriba o en manual.
enum HeadingReference {
    /// `UIInterfaceOrientation` y `CLDeviceOrientation` nombran los lados horizontales al revés: con la interfaz en
    /// «landscapeLeft» el dispositivo está en «landscapeRight» (y viceversa). Desconocida → nil (se conserva la anterior).
    static func deviceOrientation(forInterface orientation: UIInterfaceOrientation) -> CLDeviceOrientation? {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }

    /// Orientación actual de la interfaz del iPhone (la escena de la app, no la de CarPlay).
    @MainActor
    static func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }?
            .interfaceOrientation
    }
}
