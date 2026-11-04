import Foundation

/// Direct CMS fallback for local development. No configuration or service singleton
/// is read here; unit tests inject bytes instead of initializing URLSession/Firebase.
struct WebflowLiveCatalogLoader {
    struct Response: Sendable {
        let data: Data
        let status: Int
    }
    enum Failure: Error { case identifier, http(Int), envelope, changedCatalog, deadline }
    typealias Transport = @Sendable (URLRequest) async throws -> Response
    private let transport: Transport

    init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.envelope }
        return Response(data: data, status: response.statusCode)
    }) { self.transport = transport }

    static func isCMSIdentifier(_ value: String) -> Bool {
        value.count == 24 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    static func liveURL(collectionID: String, offset: Int, limit: Int = 100) throws -> URL {
        guard isCMSIdentifier(collectionID), offset >= 0, (1...100).contains(limit) else { throw Failure.identifier }
        var components = URLComponents(string: "https://api.webflow.com/v2/collections/\(collectionID)/items/live")!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit)),
                                 URLQueryItem(name: "offset", value: String(offset)),
                                 URLQueryItem(name: "sortBy", value: "createdOn"),
                                 URLQueryItem(name: "sortOrder", value: "asc")]
        return components.url!
    }

    private struct Pagination: Decodable {
        let offset: Int
        let limit: Int
        let total: Int
    }
    private struct Envelope: Decodable { let pagination: Pagination }
    private struct LiveHeader: Decodable {
        let id: String
        let isDraft: Bool
        let isArchived: Bool
        let lastPublished: String
    }

    /// Called only for bytes returned by a verified live endpoint, never staged
    /// responses, Firestore documents or cached favorites. Live fieldData remains
    /// public even if Webflow's staged-edit flag is set on a published item.
    static func normalizedLiveItem(_ data: Data) throws -> Data? {
        let header = try JSONDecoder().decode(LiveHeader.self, from: data)
        guard var item = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              isCMSIdentifier(header.id), item["fieldData"] is [String: Any],
              Article.parseWebflowTimestamp(header.lastPublished) != nil else { throw Failure.envelope }
        if header.isArchived { return nil }
        item["isDraft"] = false
        return try JSONSerialization.data(withJSONObject: item)
    }

    func load(collectionID: String, token: String, pageLimit: Int = 100) async throws -> [Data] {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.identifier }
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        var offset = 0
        var expectedTotal: Int?
        var seen = Set<String>()
        var result = [Data]()
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.deadline }
            var request = URLRequest(url: try Self.liveURL(collectionID: collectionID, offset: offset, limit: pageLimit))
            request.timeoutInterval = 20
            request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            let response = try await transport(request)
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.deadline }
            guard response.status == 200 else { throw Failure.http(response.status) }
            let pagination = try JSONDecoder().decode(Envelope.self, from: response.data).pagination
            guard let payload = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let rows = payload["items"] as? [[String: Any]], pagination.offset == offset,
                  (1...pageLimit).contains(pagination.limit), (0...10000).contains(pagination.total),
                  rows.count <= pagination.limit, offset + rows.count <= pagination.total else { throw Failure.envelope }
            if let expectedTotal, expectedTotal != pagination.total { throw Failure.changedCatalog }
            expectedTotal = pagination.total
            for row in rows {
                guard let id = row["id"] as? String, seen.insert(id).inserted else { throw Failure.changedCatalog }
                let raw = try JSONSerialization.data(withJSONObject: row)
                if let data = try Self.normalizedLiveItem(raw) { result.append(data) }
            }
            offset += rows.count
            if offset == pagination.total { return result }
            guard !rows.isEmpty else { throw Failure.envelope }
        }
    }
}
