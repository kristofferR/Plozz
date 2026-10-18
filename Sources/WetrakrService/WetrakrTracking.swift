import CoreModels
import CoreNetworking
import Foundation

struct WetrakrTrackingBody: Encodable, Sendable {
    struct Item: Encodable, Sendable {
        var id: Int?
        var ids: WetrakrIDs?
        var number: Int?
        var status: String?
        var trackedAt: String?
        var seasons: [Item]?
        var episodes: [Item]?
        enum CodingKeys: String, CodingKey {
            case id, ids, number, status, seasons, episodes, trackedAt = "tracked_at"
        }
    }
    var movies: [Item]?
    var shows: [Item]?
    var episodes: [Item]?
    var allowRewatch: Bool?
    enum CodingKeys: String, CodingKey { case movies, shows, episodes, allowRewatch = "allow_rewatch" }
}

struct WetrakrTrackingResult: Decodable, Sendable {
    struct Counts: Decodable, Sendable {
        let total: Int?
        let movies: Int?
        let shows: Int?
        let episodes: Int?
        var hasChanges: Bool { [total, movies, shows, episodes].contains { ($0 ?? 0) > 0 } }
    }
    struct StatusCounts: Decodable, Sendable {
        let total: Int?
        let planning: Counts?
        let watched: Counts?
        var hasChanges: Bool { (total ?? 0) > 0 || planning?.hasChanges == true || watched?.hasChanges == true }
    }
    struct Failure: Decodable, Sendable { let error: String? }
    let added: StatusCounts?
    let removed: StatusCounts?
    let existing: StatusCounts?
    let notFound: [String: [Failure]]?
    let errored: [String: [Failure]]?

    func validate(allowDuplicateWatch: Bool, removing: Bool = false) throws {
        if notFound?.values.contains(where: { !$0.isEmpty }) == true { throw AppError.notFound }
        let failures = errored?.values.flatMap { $0 } ?? []
        let duplicates: Set<String> = [
            "Already added!",
            "Already added! A play within the hour counts as the same watch",
            "Already added! A play on the same day counts as the same watch",
        ]
        guard failures.allSatisfy({
            guard let error = $0.error?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return (allowDuplicateWatch && duplicates.contains(error)) || (removing && error == "Nothing to remove")
        }) else { throw WetrakrError.itemRejected }
        let changed = removing ? removed?.hasChanges == true : added?.hasChanges == true || existing?.hasChanges == true
        guard changed || !failures.isEmpty
        else { throw AppError.invalidResponse }
    }
}

extension WetrakrClient {
    func tracking(
        _ body: WetrakrTrackingBody, remove: Bool = false,
        idempotencyKey: String, accessToken: String
    ) async throws {
        let endpoint = try Endpoint(
            method: .post, path: remove ? "/sync/tracking/remove" : "/sync/tracking",
            headers: ["Idempotency-Key": idempotencyKey]
        ).jsonBody(body)
        let response = try await decode(WetrakrTrackingResult.self, endpoint: endpoint, accessToken: accessToken)
        try response.validate(allowDuplicateWatch: body.allowRewatch == true, removing: remove)
    }
}
