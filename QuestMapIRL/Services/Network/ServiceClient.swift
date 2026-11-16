import Foundation

/// Política de reintentos: pocos, con espera creciente y solo para fallos recuperables.
struct RetryPolicy: Sendable {
    /// Reintentos máximos tras el primer intento.
    var maxRetries = 2
    var baseDelay: TimeInterval = 0.7
    /// Un `Retry-After` mayor que esto no se espera: se devuelve el error.
    var maxRetryAfter: TimeInterval = 4
    var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Segundos a esperar antes del siguiente intento, o nil si no se debe reintentar.
    /// `retriesDone` es el número de reintentos ya hechos.
    func delay(after error: SearchError, retriesDone: Int, retryAfter: TimeInterval?) -> TimeInterval? {
        guard retriesDone < maxRetries else { return nil }
        switch error {
        case .serviceUnavailable, .connectionLost:
            return baseDelay * pow(2, Double(retriesDone))
        case .timedOut:
            // Un servidor lento no mejora reintentando muchas veces: solo un reintento.
            return retriesDone == 0 ? baseDelay : nil
        case .rateLimited:
            if let retryAfter { return retryAfter <= maxRetryAfter ? retryAfter : nil }
            return baseDelay * pow(2, Double(retriesDone + 1))
        case .offline, .configuration, .decoding, .unexpected:
            return nil
        }
    }
}

/// Cliente para los servicios externos: clasifica cada fallo, registra un diagnóstico sin datos
/// personales y aplica `RetryPolicy`. Las cancelaciones se propagan como `CancellationError`
/// (nunca como error de conexión).
struct ServiceClient: Sendable {
    let service: String
    var session: URLSession = .shared
    var retry = RetryPolicy()
    var diagnostics: DiagnosticsLog = .shared

    func data(for request: URLRequest, operation: String) async throws -> Data {
        var retriesDone = 0
        while true {
            try Task.checkCancellation()
            let started = Date()
            let attempt = retriesDone + 1
            var failure: SearchError
            var httpStatus: Int?
            var urlCode: Int?
            var retryAfter: TimeInterval?

            do {
                let (data, response) = try await session.data(for: request)
                httpStatus = (response as? HTTPURLResponse)?.statusCode
                if let status = httpStatus, !(200..<300).contains(status) {
                    failure = SearchError.classify(httpStatus: status)
                    if let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") {
                        retryAfter = TimeInterval(header.trimmingCharacters(in: .whitespaces))
                    }
                } else {
                    record(operation, "ok", nil, nil, httpStatus, started, attempt)
                    return data
                }
            } catch is CancellationError {
                record(operation, "cancelled", nil, nil, nil, started, attempt)
                throw CancellationError()
            } catch let error as URLError {
                urlCode = error.code.rawValue
                guard let classified = SearchError.classify(error) else {
                    record(operation, "cancelled", nil, urlCode, nil, started, attempt)
                    throw CancellationError()
                }
                failure = classified
            } catch {
                failure = .unexpected
            }

            record(operation, "error", failure, urlCode, httpStatus, started, attempt)
            guard let wait = retry.delay(after: failure, retriesDone: retriesDone, retryAfter: retryAfter) else {
                throw failure
            }
            retriesDone += 1
            try await retry.sleep(wait)       // lanza CancellationError si se cancela mientras espera
        }
    }

    private func record(_ operation: String, _ outcome: String, _ error: SearchError?, _ code: Int?,
                        _ status: Int?, _ started: Date, _ attempt: Int) {
        diagnostics.record(DiagnosticEvent(
            date: Date(), service: service, operation: operation, outcome: outcome,
            errorKind: error?.kind, code: code, httpStatus: status,
            durationMs: Int(Date().timeIntervalSince(started) * 1000), attempt: attempt, note: nil))
    }
}
