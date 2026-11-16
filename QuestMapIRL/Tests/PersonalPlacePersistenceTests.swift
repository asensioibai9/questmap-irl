import XCTest
import SwiftData
@testable import QuestMapIRL

/// Casa y Trabajo: se comprueba contra un almacén REAL en disco abriendo un contenedor NUEVO sobre el mismo
/// archivo (equivale a cerrar la app del todo y volver a abrirla), no contra valores en memoria.
@MainActor
final class PersonalPlacePersistenceTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("QuestMap.store") }

    private struct Boom: Error {}

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("questmap-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        containers.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Abre un contenedor nuevo sobre el archivo del almacén (simula un arranque de la app).
    private func openContainer() throws -> ModelContainer {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(schema: AppSchema.schema, url: storeURL))
        containers.append(container) // un contexto no garantiza mantener vivo su contenedor
        return container
    }

    private var containers: [ModelContainer] = []

    private let casa = Place(id: "a", name: "Calle Mayor 12", subtitle: "Deba, Gipuzkoa", latitude: 43.2989, longitude: -2.3547)
    private let trabajo = Place(id: "b", name: "Polígono Industrial 3", subtitle: "Eibar", latitude: 43.1846, longitude: -2.4737)

    private func rows(_ container: ModelContainer, _ kind: PlaceKind) throws -> [SavedPlace] {
        let raw = kind.rawValue
        return try ModelContext(container).fetch(FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.kindRawValue == raw }))
    }

    // MARK: A / D / E / F: guardar ambos y recuperarlos en un arranque nuevo

    func testHomeAndWorkSurviveReopeningStore() throws {
        do {
            let container = try openContainer()
            let store = PersonalPlaceStore(context: ModelContext(container))
            try store.set(.home, place: casa)
            try store.set(.work, place: trabajo)
        }
        let reopened = try openContainer()
        let home = try XCTUnwrap(rows(reopened, .home).first)
        let work = try XCTUnwrap(rows(reopened, .work).first)
        XCTAssertEqual(home.name, "Casa")
        XCTAssertEqual(home.note, "Calle Mayor 12, Deba, Gipuzkoa")
        XCTAssertEqual(home.latitude, 43.2989, accuracy: 1e-9)
        XCTAssertEqual(home.longitude, -2.3547, accuracy: 1e-9)
        XCTAssertEqual(work.name, "Trabajo")
        XCTAssertEqual(work.note, "Polígono Industrial 3, Eibar")
        XCTAssertEqual(work.latitude, 43.1846, accuracy: 1e-9)
        // Se pueden usar como destino sin buscar nada por internet.
        XCTAssertEqual(home.asPlace.latitude, 43.2989, accuracy: 1e-9)
        XCTAssertEqual(work.asPlace.coordinate.longitude, -2.4737, accuracy: 1e-9)
    }

    func testSavesWithoutAnySaveOnTheContextBeingCalledByTheCaller() throws {
        // El guardado ocurre en la propia operación, no al cerrar: el contexto ni siquiera se conserva.
        do { try PersonalPlaceStore(context: ModelContext(try openContainer())).set(.home, place: casa) }
        XCTAssertEqual(try rows(try openContainer(), .home).count, 1)
    }

    // MARK: G: editar solo Casa

    func testEditingHomeKeepsWorkAndDoesNotDuplicate() throws {
        do {
            let store = PersonalPlaceStore(context: ModelContext(try openContainer()))
            try store.set(.home, place: casa)
            try store.set(.work, place: trabajo)
        }
        let newHome = Place(id: "c", name: "Avenida Nueva 5", subtitle: "Zarautz", latitude: 43.28, longitude: -2.17)
        do { try PersonalPlaceStore(context: ModelContext(try openContainer())).set(.home, place: newHome) }

        let reopened = try openContainer()
        let homes = try rows(reopened, .home)
        XCTAssertEqual(homes.count, 1)
        XCTAssertEqual(homes.first?.note, "Avenida Nueva 5, Zarautz")
        let work = try XCTUnwrap(rows(reopened, .work).first)
        XCTAssertEqual(work.note, "Polígono Industrial 3, Eibar")
        XCTAssertEqual(work.latitude, 43.1846, accuracy: 1e-9)
    }

    // MARK: H: borrar solo Trabajo

    func testDeletingWorkKeepsHomeAfterRestart() throws {
        do {
            let store = PersonalPlaceStore(context: ModelContext(try openContainer()))
            try store.set(.home, place: casa)
            try store.set(.work, place: trabajo)
        }
        do { try PersonalPlaceStore(context: ModelContext(try openContainer())).delete(.work) }

        let reopened = try openContainer()
        XCTAssertTrue(try rows(reopened, .work).isEmpty)
        XCTAssertEqual(try rows(reopened, .home).first?.note, "Calle Mayor 12, Deba, Gipuzkoa")
    }

    func testFavoritesAreNotTouchedByHomeAndWorkChanges() throws {
        do {
            let context = ModelContext(try openContainer())
            context.insert(SavedPlace(name: "Bar", note: "Pintxos", kind: .favorite, latitude: 43.3, longitude: -2.3))
            try context.save()
            let store = PersonalPlaceStore(context: context)
            try store.set(.home, place: casa)
            try store.delete(.home)
        }
        XCTAssertEqual(try rows(try openContainer(), .favorite).count, 1)
    }

    // MARK: Errores de guardado

    func testFailedCommitKeepsPreviousDataAndRetrySucceeds() throws {
        let container = try openContainer()
        let context = ModelContext(container)
        try PersonalPlaceStore(context: context).set(.home, place: casa)

        let failing = PersonalPlaceStore(context: context) { ctx in ctx.rollback(); throw Boom() }
        let newHome = Place(id: "c", name: "Otra calle 1", subtitle: "Irun", latitude: 43.33, longitude: -1.78)
        XCTAssertThrowsError(try failing.set(.home, place: newHome))

        // Los datos anteriores siguen intactos en un arranque nuevo.
        XCTAssertEqual(try rows(try openContainer(), .home).first?.note, "Calle Mayor 12, Deba, Gipuzkoa")

        // Reintentar con el guardado real funciona.
        try PersonalPlaceStore(context: ModelContext(container)).set(.home, place: newHome)
        XCTAssertEqual(try rows(try openContainer(), .home).first?.note, "Otra calle 1, Irun")
    }

    func testFailedDeleteKeepsRecord() throws {
        let context = ModelContext(try openContainer())
        try PersonalPlaceStore(context: context).set(.work, place: trabajo)
        let failing = PersonalPlaceStore(context: context) { ctx in ctx.rollback(); throw Boom() }
        XCTAssertThrowsError(try failing.delete(.work))
        XCTAssertEqual(try rows(try openContainer(), .work).count, 1)
    }

    // MARK: Duplicados y restablecer

    func testNormalizeKeepsNewestSingleRecord() throws {
        do {
            let context = ModelContext(try openContainer())
            let old = SavedPlace(name: "Casa", note: "vieja", iconName: "house.fill", kind: .home, latitude: 1, longitude: 1)
            old.createdAt = Date(timeIntervalSince1970: 1_000)
            context.insert(old)
            context.insert(SavedPlace(name: "Casa", note: "nueva", iconName: "house.fill", kind: .home, latitude: 2, longitude: 2))
            try context.save()
            PersonalPlaceStore(context: context).normalizeDuplicates()
        }
        let homes = try rows(try openContainer(), .home)
        XCTAssertEqual(homes.count, 1)
        XCTAssertEqual(homes.first?.note, "nueva")
    }

    func testEraseDeletesBothAndPersists() throws {
        do {
            let context = ModelContext(try openContainer())
            let store = PersonalPlaceStore(context: context)
            try store.set(.home, place: casa)
            try store.set(.work, place: trabajo)
            try DataEraser.eraseStoredData(context: context)
        }
        let reopened = try openContainer()
        XCTAssertTrue(try rows(reopened, .home).isEmpty)
        XCTAssertTrue(try rows(reopened, .work).isEmpty)
    }

    func testPresenceSummaryHasNoPersonalData() throws {
        let store = PersonalPlaceStore(context: ModelContext(try openContainer()))
        try store.set(.home, place: casa)
        XCTAssertEqual(store.presenceSummary, "casa=si trabajo=no")
        XCTAssertFalse(store.presenceSummary.contains("Mayor"))
    }

    // MARK: Contenedor

    func testFactoryOpensDiskStoreAsPersistent() throws {
        let outcome = ContainerFactory.make { try self.openContainer() }
        XCTAssertEqual(outcome.mode, .persistent)
    }

    func testFactoryFallsBackToTemporaryOnlyWhenDiskFailsAndNeverSilently() {
        var attempts = 0
        let outcome = ContainerFactory.make { attempts += 1; throw Boom() }
        XCTAssertEqual(outcome.mode, .temporary, "debe quedar marcado como temporal para avisar al usuario")
        XCTAssertEqual(attempts, 2, "se reintenta una vez antes de degradar")
    }

    func testTemporaryFallbackDoesNotTouchExistingDiskStore() throws {
        do { try PersonalPlaceStore(context: ModelContext(try openContainer())).set(.home, place: casa) }
        _ = ContainerFactory.make { throw Boom() }
        XCTAssertEqual(try rows(try openContainer(), .home).count, 1)
    }
}
