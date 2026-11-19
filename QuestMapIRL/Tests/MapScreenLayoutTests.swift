import SwiftUI
import XCTest
@testable import QuestMapIRL

/// Distribución de la pantalla del mapa según el espacio real (vertical, horizontal a ambos lados, iPhone pequeño y
/// grande, teclado abierto). Tamaños = área segura que recibe la vista; márgenes = cámara/isla e indicador de inicio.
final class MapScreenLayoutTests: XCTestCase {
    // Área segura aproximada de cada caso (lo que mide la vista, no la pantalla entera).
    private let portrait = MapScreenLayout(size: CGSize(width: 393, height: 759),
                                           safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    /// Horizontal con la cámara a la izquierda o a la derecha: los márgenes laterales son simétricos en iPhone.
    private let landscapeLeft = MapScreenLayout(size: CGSize(width: 734, height: 372),
                                                safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59))
    private let landscapeSmall = MapScreenLayout(size: CGSize(width: 667, height: 375))          // iPhone SE
    private let landscapeLarge = MapScreenLayout(size: CGSize(width: 814, height: 409),
                                                 safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))

    func testPortraitKeepsTheBottomPanelLayout() {
        XCTAssertFalse(portrait.isSideBySide)
        XCTAssertEqual(portrait.navigationFollowInsets.left, 0)
        XCTAssertEqual(portrait.navigationFollowInsets.bottom, 759 * 0.22, accuracy: 0.01, "igual que antes del cambio")
        XCTAssertEqual(portrait.browsingFollowInsets, .zero)
    }

    func testLandscapeUsesACompactLeftPanelThatLeavesMostOfTheMapFree() {
        for layout in [landscapeLeft, landscapeSmall, landscapeLarge] {
            XCTAssertTrue(layout.isSideBySide, "\(layout.size)")
            XCTAssertGreaterThanOrEqual(layout.sidePanelWidth, min(280, layout.size.width * 0.45), "texto y botones no se encogen")
            XCTAssertLessThanOrEqual(layout.sidePanelWidth, 380)
            XCTAssertLessThanOrEqual(layout.sidePanelWidth, layout.size.width * 0.45, "el mapa es la parte principal")
            XCTAssertGreaterThan(layout.freeMapWidth, 240, "queda un hueco útil entre panel y controles")
        }
        XCTAssertGreaterThan(landscapeLarge.sidePanelWidth, landscapeSmall.sidePanelWidth - 0.5, "proporcional, no fijo")
    }

    func testControlsFitInTheUsableHeightOfASmallIPhone() {
        let fourButtons: CGFloat = 4 * 44 + 3 + 6                    // grupo compacto: 4 botones, separadores, borde
        let attribution: CGFloat = 30
        XCTAssertLessThan(fourButtons + 8 + attribution, landscapeSmall.size.height - 14)
    }

    func testNavigationCameraCentersTheUserInTheFreeAreaNotBehindTheColumn() {
        let insets = landscapeLeft.navigationFollowInsets
        XCTAssertGreaterThan(insets.left, landscapeLeft.sidePanelWidth + landscapeLeft.safeArea.leading)
        XCTAssertLessThan(insets.bottom, landscapeLeft.size.height * 0.3)
        let screenWidth = landscapeLeft.size.width + landscapeLeft.safeArea.leading + landscapeLeft.safeArea.trailing
        let freeCenter = insets.left + (screenWidth - insets.left - insets.right) / 2
        XCTAssertGreaterThan(freeCenter, insets.left, "la flecha queda a la derecha de la columna")
        XCTAssertLessThan(freeCenter, screenWidth - 60, "y no pegada a los botones")
    }

    func testRouteFramingAvoidsTheColumnAndTheButtons() {
        for insets in [landscapeLeft.fullRouteInsets, landscapeLeft.previewRouteInsets] {
            XCTAssertGreaterThan(insets.left, landscapeLeft.sidePanelWidth)
            XCTAssertGreaterThanOrEqual(insets.right, 76)
        }
        XCTAssertEqual(portrait.previewRouteInsets.bottom, 759 * 0.55, accuracy: 0.01)
    }

    func testTallOrLargeSurfacesAreNotTreatedAsLandscapePhone() {
        XCTAssertFalse(MapScreenLayout(size: CGSize(width: 1024, height: 700)).isSideBySide)
        XCTAssertFalse(MapScreenLayout(size: CGSize(width: 500, height: 400)).isSideBySide, "demasiado estrecho para una columna")
    }

    func testKeyboardShrinksThePanelButKeepsTheLayout() {
        let keyboard = MapScreenLayout(size: CGSize(width: 734, height: 170),
                                       safeArea: EdgeInsets(top: 0, leading: 59, bottom: 200, trailing: 59))
        XCTAssertTrue(keyboard.isSideBySide, "abrir el teclado no cambia de distribución")
        XCTAssertLessThanOrEqual(keyboard.sidePanelMaxHeight, 170, "campo y resultados por encima del teclado")
        XCTAssertLessThanOrEqual(landscapeLeft.sidePanelMaxHeight, landscapeLeft.size.height)
    }

    func testFollowCameraUsesOnlyTheLeftPanelMarginSoTheCompassStaysInTheControlColumn() {
        // MapLibre coloca la brújula respecto a los márgenes de la cámara: sin margen derecho no se desplaza al centro.
        XCTAssertEqual(landscapeLeft.browsingFollowInsets.right, 0)
        XCTAssertEqual(landscapeLeft.navigationFollowInsets.right, 0)
        // Aun así, el centro del hueco queda lejos de la columna de controles.
        let screenWidth = landscapeLeft.size.width + landscapeLeft.safeArea.leading + landscapeLeft.safeArea.trailing
        let center = landscapeLeft.navigationFollowInsets.left + (screenWidth - landscapeLeft.navigationFollowInsets.left) / 2
        XCTAssertLessThan(center, screenWidth - landscapeLeft.safeArea.trailing - 12 - MapScreenLayout.controlsWidth - 80)
        // El encuadre de la ruta completa sí deja sitio a los controles (usa márgenes de encuadre, no de la cámara).
        XCTAssertGreaterThanOrEqual(landscapeLeft.fullRouteInsets.right, landscapeLeft.safeArea.trailing + MapScreenLayout.controlsWidth)
    }

    func testRotatingBackAndForthGivesTheSameLayout() {
        let again = MapScreenLayout(size: CGSize(width: 393, height: 759),
                                    safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(again, portrait)
        XCTAssertEqual(again.navigationFollowInsets, portrait.navigationFollowInsets)
    }
}
