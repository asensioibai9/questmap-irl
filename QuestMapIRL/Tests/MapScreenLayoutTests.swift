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

    func testLandscapeUsesASideColumnThatLeavesMostOfTheMapFree() {
        for layout in [landscapeLeft, landscapeSmall, landscapeLarge] {
            XCTAssertTrue(layout.isSideBySide, "\(layout.size)")
            XCTAssertGreaterThanOrEqual(layout.sidePanelWidth, 300, "texto y botones no se encogen")
            XCTAssertLessThanOrEqual(layout.sidePanelWidth, 400)
            XCTAssertLessThanOrEqual(layout.sidePanelWidth, layout.size.width * 0.5, "el mapa conserva al menos la mitad")
        }
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

    func testKeyboardShrinksTheColumnButKeepsTheLayout() {
        let keyboard = MapScreenLayout(size: CGSize(width: 734, height: 170),
                                       safeArea: EdgeInsets(top: 0, leading: 59, bottom: 200, trailing: 59))
        XCTAssertTrue(keyboard.isSideBySide, "abrir el teclado no cambia de distribución")
        XCTAssertLessThanOrEqual(keyboard.sidePanelHeight(for: .large), 170, "campo y resultados por encima del teclado")
    }

    func testSideColumnHeightsMatchTheThreeSheetSizes() {
        let compact = landscapeLeft.sidePanelHeight(for: .compactPanel)
        let medium = landscapeLeft.sidePanelHeight(for: .medium)
        let large = landscapeLeft.sidePanelHeight(for: .large)
        XCTAssertEqual(compact, 118)
        XCTAssertLessThan(compact, medium)
        XCTAssertLessThanOrEqual(medium, large)
        XCTAssertLessThanOrEqual(large, landscapeLeft.size.height)
    }

    func testRotatingBackAndForthGivesTheSameLayout() {
        let again = MapScreenLayout(size: CGSize(width: 393, height: 759),
                                    safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(again, portrait)
        XCTAssertEqual(again.navigationFollowInsets, portrait.navigationFollowInsets)
    }
}
