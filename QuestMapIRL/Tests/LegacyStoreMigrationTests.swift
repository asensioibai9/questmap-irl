import XCTest
import CoreData
import SwiftData
@testable import QuestMapIRL

/// Reproduce una instalación EXISTENTE: se crea en disco un almacén con el esquema de la primera versión
/// (MVP, commit de4aad2: UserSettings sin headingUp/showCompass) y se abre con el esquema actual.
@MainActor
final class LegacyStoreMigrationTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("default.store") }
    private var containers: [ModelContainer] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("questmap-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        containers.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }

    /// Almacén tal y como lo dejaba la primera versión de la app.
    private func writeVersion0Store() throws {
        let settings = NSEntityDescription()
        settings.name = "UserSettings"
        settings.properties = [attribute("themeRawValue", .stringAttributeType),
                               attribute("useMetricUnits", .booleanAttributeType),
                               attribute("voiceEnabled", .booleanAttributeType),
                               attribute("nightModeOverride", .stringAttributeType)]
        let place = NSEntityDescription()
        place.name = "SavedPlace"
        place.properties = [attribute("name", .stringAttributeType), attribute("note", .stringAttributeType),
                            attribute("iconName", .stringAttributeType), attribute("kindRawValue", .stringAttributeType),
                            attribute("latitude", .doubleAttributeType), attribute("longitude", .doubleAttributeType),
                            attribute("createdAt", .dateAttributeType)]
        let model = NSManagedObjectModel()
        model.entities = [settings, place]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL,
                                                       options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]])
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let s = NSManagedObject(entity: settings, insertInto: context)
            s.setValue("neonNocturno", forKey: "themeRawValue")
            s.setValue(false, forKey: "useMetricUnits")
            s.setValue(true, forKey: "voiceEnabled")
            s.setValue("auto", forKey: "nightModeOverride")
            let p = NSManagedObject(entity: place, insertInto: context)
            p.setValue("Casa", forKey: "name")
            p.setValue("Calle Antigua 1, Deba", forKey: "note")
            p.setValue("house.fill", forKey: "iconName")
            p.setValue("home", forKey: "kindRawValue")
            p.setValue(43.3, forKey: "latitude")
            p.setValue(-2.35, forKey: "longitude")
            p.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "createdAt")
            try context.save()
        }
        try coordinator.remove(store)
    }

    private func open() throws -> ModelContainer {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(schema: AppSchema.schema, url: storeURL))
        containers.append(container)
        return container
    }

    func testStoreFromFirstVersionOpensAndKeepsUserData() throws {
        try writeVersion0Store()
        let outcome = ContainerFactory.make { try self.open() }
        XCTAssertEqual(outcome.mode, .persistent, "un almacén de una versión anterior debe abrirse, no degradarse a temporal")

        let context = ModelContext(outcome.container)
        let places = try context.fetch(FetchDescriptor<SavedPlace>())
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.note, "Calle Antigua 1, Deba")
        XCTAssertEqual(places.first?.latitude ?? 0, 43.3, accuracy: 1e-9)

        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.themeRawValue, "neonNocturno")
        XCTAssertFalse(settings.useMetricUnits)
        XCTAssertTrue(settings.headingUp, "campo nuevo: valor por defecto")
        XCTAssertTrue(settings.showCompass, "campo nuevo: valor por defecto")
    }

    func testMigratedStoreKeepsDataAfterAnotherLaunch() throws {
        try writeVersion0Store()
        _ = try open()
        containers.removeAll()
        let second = try open()
        XCTAssertEqual(try ModelContext(second).fetch(FetchDescriptor<SavedPlace>()).count, 1)
    }

    // MARK: Copias de seguridad (nunca se borra el original)

    func testBackupCopiesStoreOncePerVersionAndKeepsOriginal() throws {
        try writeVersion0Store()
        let defaults = UserDefaults(suiteName: "questmap-test-\(UUID().uuidString)")!
        let backups = directory.appendingPathComponent("backups")
        let first = StoreBackup.backupIfNeeded(storeURL: storeURL, tag: "1.0-1", defaults: defaults, backupsDirectory: backups)
        XCTAssertNotNil(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first).appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "el original sigue en su sitio")
        XCTAssertNil(StoreBackup.backupIfNeeded(storeURL: storeURL, tag: "1.0-1", defaults: defaults, backupsDirectory: backups),
                     "no se repite para la misma versión")
    }

    func testSetAsideMovesFilesWithoutDeletingThem() throws {
        try writeVersion0Store()
        let backups = directory.appendingPathComponent("backups")
        let folder = try StoreBackup.setAside(storeURL: storeURL, backupsDirectory: backups)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("default.store").path))
    }

    func testErrorInfoHasDomainAndCodeOnly() {
        let error = NSError(domain: "NSCocoaErrorDomain", code: 134110,
                            userInfo: [NSUnderlyingErrorKey: NSError(domain: "NSSQLiteErrorDomain", code: 1)])
        XCTAssertTrue(StorageErrorInfo.describe(error).hasPrefix("NSCocoaErrorDomain#134110 > NSSQLiteErrorDomain#1"))
    }
}
