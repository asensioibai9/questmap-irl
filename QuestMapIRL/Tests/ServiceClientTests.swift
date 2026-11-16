import XCTest
@testable import QuestMapIRL

final class ServiceClientTests: XCTestCase {
    private var diagnostics: DiagnosticsLog!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        diagnostics = DiagnosticsLog()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(retries: Int = 2) -> ServiceClient {
        ServiceClient(service: "test", session: StubURLProtocol.session(), retry: instantRetry(maxRetries: retries), diagnostics: diagnostics)
    }

    private let request = URLRequest(url: URL(string: "https://example.test/search?q=x")!)

    func testSuccessIsRecordedWithoutPersonalData() async throws {
        StubURLProtocol.responder = { _ in ok(Data("hola".utf8)) }
        let data = try await makeClient().data(for: request, operation: "search")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hola")
        let event = try XCTUnwrap(diagnostics.events.last)
        XCTAssertEqual(event.outcome, "ok")
        XCTAssertEqual(event.httpStatus, 200)
        XCTAssertFalse(event.summary.contains("example.test"))
        XCTAssertFalse(event.summary.contains("q=x"))
    }

    func testServerErrorIsRetriedThenSucceeds() async throws {
        var calls = 0
        StubURLProtocol.responder = { _ in
            calls += 1
            return calls == 1 ? http(502, "capacity") : ok(Data("ok".utf8))
        }
        _ = try await makeClient().data(for: request, operation: "search")
        XCTAssertEqual(calls, 2)
        let outcomes = diagnostics.events.map { "\($0.outcome):\($0.httpStatus ?? 0):\($0.attempt)" }
        XCTAssertEqual(outcomes, ["error:502:1", "ok:200:2"])
    }

    func testRetriesAreLimited() async {
        StubURLProtocol.responder = { _ in http(503) }
        do {
            _ = try await makeClient(retries: 2).data(for: request, operation: "search")
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .serviceUnavailable)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 3)      // 1 intento + 2 reintentos
    }

    func testRateLimitHonoursShortRetryAfterAndSkipsLongOne() async throws {
        var calls = 0
        StubURLProtocol.responder = { _ in
            calls += 1
            return calls == 1 ? http(429, "", headers: ["Retry-After": "2"]) : ok(Data())
        }
        _ = try await makeClient().data(for: request, operation: "search")
        XCTAssertEqual(calls, 2)

        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in http(429, "", headers: ["Retry-After": "120"]) }
        do {
            _ = try await makeClient().data(for: request, operation: "search")
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .rateLimited)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testConfigurationErrorsAreNotRetried() async {
        for status in [400, 401, 403, 404] {
            StubURLProtocol.reset()
            StubURLProtocol.responder = { _ in http(status) }
            do {
                _ = try await makeClient().data(for: request, operation: "search")
                XCTFail("Debía fallar")
            } catch {
                XCTAssertEqual(error as? SearchError, .configuration, "HTTP \(status)")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, "HTTP \(status) no se reintenta")
        }
    }

    func testTimeoutIsReportedAsTimeoutNotOffline() async {
        StubURLProtocol.responder = { _ in .failure(URLError(.timedOut)) }
        do {
            _ = try await makeClient().data(for: request, operation: "search")
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .timedOut)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)       // un único reintento
        XCTAssertEqual(diagnostics.events.first?.code, URLError.timedOut.rawValue)
    }

    func testRealOfflineIsNotRetriedAndIsReportedAsOffline() async {
        StubURLProtocol.responder = { _ in .failure(URLError(.notConnectedToInternet)) }
        do {
            _ = try await makeClient().data(for: request, operation: "search")
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? SearchError, .offline)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testURLCancellationBecomesCancellationErrorNotAConnectionError() async {
        StubURLProtocol.responder = { _ in .failure(URLError(.cancelled)) }
        do {
            _ = try await makeClient().data(for: request, operation: "search")
            XCTFail("Debía lanzar cancelación")
        } catch {
            XCTAssertTrue(error is CancellationError)
            XCTAssertNil(error as? SearchError)
        }
        XCTAssertEqual(diagnostics.events.last?.outcome, "cancelled")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testDiagnosticsLogIsCircularAndPersistent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = DiagnosticsLog(fileURL: file, capacity: 3)
        for i in 0..<5 {
            log.record(DiagnosticEvent(date: Date(), service: "s", operation: "op\(i)", outcome: "ok", errorKind: nil,
                                       code: nil, httpStatus: 200, durationMs: i, attempt: 1, note: nil))
        }
        XCTAssertEqual(log.events.map(\.operation), ["op2", "op3", "op4"])
        log.flush()                                              // espera a la escritura en segundo plano
        XCTAssertEqual(DiagnosticsLog(fileURL: file, capacity: 3).events.map(\.operation), ["op2", "op3", "op4"])
        XCTAssertTrue(log.report(header: ["cabecera"]).contains("cabecera"))
    }
}
