import CoreModels
import CoreNetworking
import Foundation

actor WetrakrRequestGate {
    static let shared = WetrakrRequestGate()
    private let limiter = ConcurrencyLimiter(limit: 1)
    private var retryAfter: Date?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await limiter.run {
            try await self.checkCooldown()
            do { return try await operation() }
            catch AppError.rateLimited(let delay) {
                await self.throttle(delay)
                throw AppError.rateLimited(retryAfter: delay)
            }
        }
    }

    private func checkCooldown() throws {
        if let retryAfter, retryAfter > Date() {
            throw AppError.rateLimited(retryAfter: retryAfter.timeIntervalSinceNow)
        }
    }
    private func throttle(_ seconds: TimeInterval?) {
        retryAfter = Date().addingTimeInterval(max(1, seconds ?? 60))
    }
}

struct WetrakrClient: Sendable {
    let config: WetrakrConfig
    let http: any HTTPClient
    let gate: WetrakrRequestGate

    init(config: WetrakrConfig, http: any HTTPClient, gate: WetrakrRequestGate = .shared) {
        self.config = config
        self.http = http
        self.gate = gate
    }

    func send(_ endpoint: Endpoint, accessToken: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let clientID = config.clientID else { throw WetrakrError.clientRejected }
        var endpoint = endpoint
        endpoint.headers["wetrakr-api-key"] = clientID
        endpoint.headers["wetrakr-api-version"] = "1"
        endpoint.headers["Accept"] = "application/json"
        if let accessToken { endpoint.headers["Authorization"] = "Bearer \(accessToken)" }
        endpoint.redirectPolicy = .sameOrigin
        let request = endpoint
        return try await gate.run {
            let (data, response) = try await http.sendRaw(request, baseURL: config.apiBaseURL)
            if (200...299).contains(response.statusCode) { return (data, response) }
            if request.path == "/oauth/token" {
                PlozzLog.networking.error("WeTrakr authorization-code exchange rejected: HTTP \(response.statusCode)")
                if response.statusCode == 400 { throw WetrakrError.authorizationCodeRejected }
            }
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            switch (response.statusCode, error?.error) {
            case (400, "authorization_pending"): throw WetrakrError.authorizationPending
            case (400, "JOURNAL_EXPIRED"): throw WetrakrError.journalExpired
            case (410, _): throw AppError.quickConnectExpired
            case (418, _): throw WetrakrError.accessDenied
            case (423, _), (401, "invalid_client"): throw WetrakrError.clientRejected
            case (401, _): throw AppError.unauthorized
            case (403, _): throw WetrakrError.requestBlocked
            case (404, _): throw AppError.notFound
            case (429, _):
                let raw = response.value(forHTTPHeaderField: "Retry-After")
                let delay = raw.flatMap(Double.init) ?? raw.flatMap { value -> TimeInterval? in
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                    return formatter.date(from: value)?.timeIntervalSinceNow
                }
                throw AppError.rateLimited(retryAfter: delay.flatMap { $0.isFinite ? max(0, $0) : nil })
            default: throw AppError.invalidResponse
            }
        }
    }

    func decode<T: Decodable & Sendable>(
        _ type: T.Type, endpoint: Endpoint, accessToken: String? = nil
    ) async throws -> T {
        let (data, _) = try await send(endpoint, accessToken: accessToken)
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            PlozzLog.networking.error("WeTrakr response could not be decoded")
            throw AppError.decoding
        }
    }

    func page<T: Decodable & Sendable>(
        _ type: T.Type, path: String, page: Int, query: [URLQueryItem] = [], accessToken: String
    ) async throws -> (T, hasNext: Bool) {
        let (data, response) = try await send(Endpoint(path: path, queryItems: query + [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: "100"),
        ]), accessToken: accessToken)
        guard let rawPages = response.value(forHTTPHeaderField: "X-Pagination-Page-Count"),
              let pages = Int(rawPages), pages >= 0, page <= max(1, pages)
        else { throw AppError.invalidResponse }
        do { return (try JSONDecoder().decode(type, from: data), page < pages) }
        catch { throw AppError.decoding }
    }

    private struct ErrorResponse: Decodable { let error: String? }
}
