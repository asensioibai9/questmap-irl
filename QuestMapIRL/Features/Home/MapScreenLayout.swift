import SwiftUI
import UIKit

/// Distribución de la pantalla del mapa calculada a partir del espacio REAL disponible (no del modelo de iPhone ni de
/// la orientación declarada): se recalcula cada vez que cambia el tamaño (giro, multitarea, teclado).
///
/// - Vertical (o cualquier superficie alta): panel inferior y HUD de navegación arriba y abajo, como hasta ahora.
/// - Apaisado bajo (iPhone en horizontal): panel compacto a la izquierda, controles agrupados a la derecha y el mapa
///   libre en medio; la cámara coloca al usuario en el centro de ese hueco.
struct MapScreenLayout: Equatable {
    /// Tamaño del área segura de la pantalla (sin cámara, isla ni indicador de inicio).
    var size: CGSize
    /// Márgenes de área segura alrededor de `size` (la cámara del mapa se mide sobre la pantalla entera).
    var safeArea: EdgeInsets

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.safeArea = safeArea
    }

    /// Margen entre los paneles y el borde del área segura.
    static let edgeMargin: CGFloat = 12
    /// Botones del grupo de controles: 52 pt cuando hay alto de sobra (iPhone grande en horizontal) y 44 pt, el mínimo
    /// táctil de Apple, si no. Cuatro botones caben así en la altura útil de cualquier iPhone.
    var controlButtonSize: CGFloat { size.height >= 390 ? 52 : 44 }
    /// Ancho del grupo de controles de la derecha (botón + borde).
    var controlsWidth: CGFloat { controlButtonSize + 6 }

    /// Más ancho que alto y poco alto: no cabe un panel inferior sin tapar casi todo el mapa.
    var isSideBySide: Bool { size.width > size.height && size.height < 560 && size.width >= 560 }

    /// Ancho del panel izquierdo: proporcional al ancho, entre 280 y 380 pt (legible con texto grande) y nunca más del 45 %
    /// del ancho, para que el mapa quede siempre como la parte principal.
    var sidePanelWidth: CGFloat {
        min(size.width * 0.45, min(380, max(280, size.width * 0.36)))
    }

    /// Alto máximo del panel izquierdo: el alto útil (ya sin teclado) menos los márgenes. En estado reducido mide solo lo
    /// que ocupa su contenido.
    var sidePanelMaxHeight: CGFloat { max(120, size.height - 8 - 6) }

    /// Espacio que el panel izquierdo ocupa desde el borde izquierdo de la PANTALLA.
    private var leftOccupied: CGFloat { safeArea.leading + Self.edgeMargin + sidePanelWidth + Self.edgeMargin }
    /// Espacio que los controles ocupan desde el borde derecho de la PANTALLA.
    private var rightOccupied: CGFloat { safeArea.trailing + Self.edgeMargin + controlsWidth + Self.edgeMargin }

    /// Ancho de mapa que queda libre entre el panel y los controles.
    var freeMapWidth: CGFloat {
        size.width + safeArea.leading + safeArea.trailing - leftOccupied - rightOccupied
    }

    /// Márgenes de la cámara de seguimiento durante la navegación. Solo a la izquierda (panel) y abajo: MapLibre coloca la
    /// brújula del mapa respecto a estos márgenes, y un margen derecho la sacaba de la columna de controles al centro del
    /// mapa. La columna derecha es estrecha (≈ 74 pt): con el panel a la izquierda descontado, el usuario ya queda lejos.
    var navigationFollowInsets: UIEdgeInsets {
        if isSideBySide {
            // Usuario en el hueco libre, algo bajo para ver más carretera por delante.
            return UIEdgeInsets(top: 0, left: leftOccupied, bottom: size.height * 0.18, right: 0)
        }
        return UIEdgeInsets(top: 0, left: 0, bottom: size.height * 0.22, right: 0)
    }

    /// Márgenes de la cámara de seguimiento sin ruta: con panel lateral, el usuario queda en el centro del mapa libre.
    var browsingFollowInsets: UIEdgeInsets {
        isSideBySide ? UIEdgeInsets(top: 0, left: leftOccupied, bottom: 0, right: 0) : .zero
    }

    /// Encuadre de la ruta completa durante la navegación.
    var fullRouteInsets: UIEdgeInsets {
        if isSideBySide { return sideRouteInsets }
        return UIEdgeInsets(top: size.height * 0.18, left: 40, bottom: size.height * 0.38, right: 40)
    }

    /// Encuadre de la vista previa de la ruta (panel con alternativas abierto).
    var previewRouteInsets: UIEdgeInsets {
        if isSideBySide { return sideRouteInsets }
        return UIEdgeInsets(top: size.height * 0.18, left: 40, bottom: size.height * 0.55, right: 40)
    }

    private var sideRouteInsets: UIEdgeInsets {
        UIEdgeInsets(top: safeArea.top + 44, left: leftOccupied + 12, bottom: safeArea.bottom + 28, right: rightOccupied + 12)
    }
}
