import XCTest
@testable import QuestMapIRL

/// Cada tipo de fallo tiene su causa y su mensaje; solo los problemas de conexión reales se
/// presentan como "sin conexión".
final class SearchErrorTests: XCTestCase {
    func testURLErrorsAreClassifiedByRealCause() {
        XCTAssertEqual(SearchError.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(SearchError.classify(URLError(.dataNotAllowed)), .offline)
        XCTAssertEqual(SearchError.classify(URLError(.networkConnectionLost)), .connectionLost)
        XCTAssertEqual(SearchError.classify(URLError(.timedOut)), .timedOut)
        XCTAssertEqual(SearchError.classify(URLError(.cannotFindHost)), .serviceUnavailable)
        XCTAssertEqual(SearchError.classify(URLError(.cannotConnectToHost)), .serviceUnavailable)
        XCTAssertEqual(SearchError.classify(URLError(.secureConnectionFailed)), .configuration)
        XCTAssertEqual(SearchError.classify(URLError(.badServerResponse)), .decoding)
        XCTAssertEqual(SearchError.classify(URLError(.unknown)), .unexpected)
    }

    func testCancellationIsNotAnError() {
        XCTAssertNil(SearchError.classify(URLError(.cancelled)))
    }

    func testHTTPStatusesAreClassified() {
        XCTAssertEqual(SearchError.classify(httpStatus: 429), .rateLimited)
        XCTAssertEqual(SearchError.classify(httpStatus: 401), .configuration)
        XCTAssertEqual(SearchError.classify(httpStatus: 403), .configuration)
        XCTAssertEqual(SearchError.classify(httpStatus: 404), .configuration)
        XCTAssertEqual(SearchError.classify(httpStatus: 408), .timedOut)
        XCTAssertEqual(SearchError.classify(httpStatus: 500), .serviceUnavailable)
        XCTAssertEqual(SearchError.classify(httpStatus: 502), .serviceUnavailable)
        XCTAssertEqual(SearchError.classify(httpStatus: 503), .serviceUnavailable)
        XCTAssertEqual(SearchError.classify(httpStatus: 504), .serviceUnavailable)
    }

    func testOnlyRealConnectionProblemsMentionConnection() {
        XCTAssertTrue(SearchError.offline.isConnectionProblem)
        XCTAssertTrue(SearchError.connectionLost.isConnectionProblem)
        for error in [SearchError.timedOut, .serviceUnavailable, .rateLimited, .configuration, .decoding, .unexpected] {
            XCTAssertFalse(error.isConnectionProblem, "\(error.kind) no es un problema de conexión")
            XCTAssertFalse(error.userMessage.lowercased().contains("sin conexión"), "\(error.kind) no debe decir «sin conexión»")
        }
    }

    func testEveryErrorHasItsOwnMessage() {
        let all: [SearchError] = [.offline, .connectionLost, .timedOut, .serviceUnavailable, .rateLimited, .configuration, .decoding, .unexpected]
        XCTAssertEqual(Set(all.map(\.userMessage)).count, all.count)
        XCTAssertEqual(Set(all.map(\.kind)).count, all.count)
    }

    func testRoutingErrorsKeepTheirCause() {
        XCTAssertEqual(RoutingError(.timedOut), .timedOut)
        XCTAssertEqual(RoutingError(.serviceUnavailable), .server)
        XCTAssertEqual(RoutingError(.rateLimited), .rateLimited)
        XCTAssertEqual(RoutingError(.offline), .offline)
        XCTAssertNotEqual(RoutingError.timedOut.errorDescription, RoutingError.offline.errorDescription)
    }

    func testRetryPolicyOnlyRetriesRecoverableErrorsAndIsBounded() {
        let policy = instantRetry(maxRetries: 2)
        XCTAssertNotNil(policy.delay(after: .serviceUnavailable, retriesDone: 0, retryAfter: nil))
        XCTAssertNotNil(policy.delay(after: .serviceUnavailable, retriesDone: 1, retryAfter: nil))
        XCTAssertNil(policy.delay(after: .serviceUnavailable, retriesDone: 2, retryAfter: nil))      // límite
        XCTAssertNotNil(policy.delay(after: .timedOut, retriesDone: 0, retryAfter: nil))
        XCTAssertNil(policy.delay(after: .timedOut, retriesDone: 1, retryAfter: nil))                // un solo reintento
        XCTAssertNil(policy.delay(after: .offline, retriesDone: 0, retryAfter: nil))
        XCTAssertNil(policy.delay(after: .configuration, retriesDone: 0, retryAfter: nil))
        XCTAssertNil(policy.delay(after: .decoding, retriesDone: 0, retryAfter: nil))
        XCTAssertEqual(policy.delay(after: .rateLimited, retriesDone: 0, retryAfter: 2), 2)
        XCTAssertNil(policy.delay(after: .rateLimited, retriesDone: 0, retryAfter: 60))              // espera excesiva
    }
}
