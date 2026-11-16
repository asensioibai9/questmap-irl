import XCTest
@testable import QuestMapIRL

final class InstructionBuilderTests: XCTestCase {
    private func build(_ type: String, _ modifier: String? = nil, name: String? = nil,
                       exit: Int? = nil, exits: String? = nil) -> InstructionBuilder.Result {
        InstructionBuilder.build(type: type, modifier: modifier, name: name, exit: exit, exits: exits)
    }

    func testTurnRightOntoStreet() {
        let r = build("turn", "right", name: "Calle de Alcalá")
        XCTAssertEqual(r.text, "Gira a la derecha en Calle de Alcalá")
        XCTAssertEqual(r.symbol, "arrow.turn.up.right")
    }

    func testSlightLeftAndSharpRight() {
        XCTAssertEqual(build("turn", "slight left").text, "Gira ligeramente a la izquierda")
        XCTAssertEqual(build("turn", "sharp right").text, "Gira de forma cerrada a la derecha")
    }

    func testUTurn() {
        let r = build("turn", "uturn")
        XCTAssertEqual(r.text, "Haz un cambio de sentido")
        XCTAssertEqual(r.symbol, "arrow.uturn.left")
    }

    func testStraightContinues() {
        XCTAssertEqual(build("turn", "straight", name: "Gran Vía").text, "Continúa recto por Gran Vía")
        XCTAssertEqual(build("new name", name: "Paseo del Prado").text, "Continúa por Paseo del Prado")
    }

    func testRoundaboutExitIsOrdinal() {
        XCTAssertEqual(build("roundabout", exit: 2).text, "En la rotonda, toma la segunda salida")
        XCTAssertEqual(build("rotary", exit: 11).text, "En la rotonda, toma la 11ª salida")
        XCTAssertEqual(build("roundabout").text, "Entra en la rotonda")
    }

    func testMergeAndRamps() {
        XCTAssertEqual(build("merge", "slight left", name: "A-6").text, "Incorpórate por la izquierda a A-6")
        XCTAssertEqual(build("off ramp", "slight right", name: "Madrid", exits: "5").text, "Toma la salida 5 a la derecha hacia Madrid")
        XCTAssertEqual(build("on ramp", "right", name: "M-30").text, "Toma la incorporación a la derecha a M-30")
    }

    func testArrivalSide() {
        XCTAssertEqual(build("arrive").text, "Has llegado a tu destino")
        XCTAssertEqual(build("arrive", "left").text, "Has llegado a tu destino, a la izquierda")
        XCTAssertEqual(build("arrive").symbol, "flag.checkered")
    }

    func testUnknownTypeNeverInventsATurn() {
        let r = build("something new", "right", name: "Calle X")
        XCTAssertEqual(r.text, "Continúa por Calle X")
        XCTAssertFalse(r.text.contains("Gira"))
    }
}
