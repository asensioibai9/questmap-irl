import CarPlay
import XCTest
@testable import QuestMapIRL

/// Lo que la app tiene que declarar para que CarPlay pueda crear su escena. NO comprueba el permiso de Apple ni la firma:
/// eso solo se ve en la app firmada (ver el paso de verificación del workflow de firma).
final class CarPlaySceneConfigurationTests: XCTestCase {
    private var appInfo: [String: Any] { Bundle(for: CarPlaySceneDelegate.self).infoDictionary ?? [:] }

    func testInfoPlistDeclaresTheMainCarPlayScene() throws {
        let manifest = try XCTUnwrap(appInfo["UIApplicationSceneManifest"] as? [String: Any])
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, true)
        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
        let carPlay = try XCTUnwrap((configurations["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]])?.first)
        XCTAssertEqual(carPlay["UISceneClassName"] as? String, "CPTemplateApplicationScene")
        let delegateName = try XCTUnwrap(carPlay["UISceneDelegateClassName"] as? String)
        XCTAssertFalse(delegateName.contains("$("), "la variable del módulo debe sustituirse al compilar")
        XCTAssertTrue(NSClassFromString(delegateName) === CarPlaySceneDelegate.self, "el delegado declarado existe: \(delegateName)")
    }

    func testDelegateImplementsTheNavigationConnectionMethodsWithTheExactSignature() {
        // Métodos opcionales de Objective-C: si la firma no coincide (p. ej. UIWindow en vez de CPWindow) nunca se llaman.
        XCTAssertTrue(CarPlaySceneDelegate.instancesRespond(
            to: #selector(CPTemplateApplicationSceneDelegate.templateApplicationScene(_:didConnect:to:))))
        XCTAssertTrue(CarPlaySceneDelegate.instancesRespond(
            to: #selector(CPTemplateApplicationSceneDelegate.templateApplicationScene(_:didDisconnect:from:))))
        // Solo un método de conexión (Apple: implementar solo uno; el de ventana es el de las apps de navegación).
        XCTAssertFalse(CarPlaySceneDelegate.instancesRespond(
            to: #selector(CPTemplateApplicationSceneDelegate.templateApplicationScene(_:didConnect:))))
    }

    func testIPhoneSceneIsNotForcedIntoCarPlayAndBackgroundModesAreTheExistingOnes() throws {
        let modes = try XCTUnwrap(appInfo["UIBackgroundModes"] as? [String])
        XCTAssertEqual(Set(modes), ["location", "audio"])
        let manifest = try XCTUnwrap(appInfo["UIApplicationSceneManifest"] as? [String: Any])
        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
        XCTAssertNil(configurations["CPTemplateApplicationDashboardSceneSessionRoleApplication"], "sin Dashboard (no implementado)")
    }
}
