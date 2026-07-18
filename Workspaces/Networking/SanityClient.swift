import Foundation

/// A minimal client for the public, read-only Sanity Content Lake query API
/// backing workspaces.xyz.
struct SanityClient {
    static let shared = SanityClient()

    private let endpoint = URL(string: "https://ui5qde1a.apicdn.sanity.io/v2024-01-01/data/query/production")!
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.isoFractional.date(from: string) ?? Self.iso.date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date: \(string)"
            ))
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso = ISO8601DateFormatter()

    /// Runs a GROQ query and decodes the `result` field of the response envelope.
    func fetch<T: Decodable>(_ type: T.Type, query: String) async throws -> T {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(Envelope<T>.self, from: data).result
    }

    private struct Envelope<T: Decodable>: Decodable {
        let result: T
    }
}

// MARK: - Queries

enum GROQ {
    static let pageSize = 20

    private static let notDraft = #"!(_id in path("drafts.**"))"#

    private static let summaryProjection = """
        {issueNumber, "slug": slug.current, guestName, guestTitle, guestLocation, publishedAt, \
        "hero": photos[0]{alt, "url": asset->url}, "photoCount": count(photos), \
        "tags": tags[]->{name, "slug": slug.current}}
        """

    /// Feed page, optionally narrowed to a tag and/or a guest-name prefix search.
    static func setups(offset: Int, limit: Int = pageSize, tagSlug: String? = nil, search: String? = nil) -> String {
        var filters = [#"_type=="setup""#, notDraft]
        if let tagSlug {
            filters.append("\"\(escape(tagSlug))\" in tags[]->slug.current")
        }
        if let search, !search.isEmpty {
            filters.append("guestName match \"\(escape(search))*\"")
        }
        let filter = filters.joined(separator: " && ")
        return "*[\(filter)] | order(issueNumber desc)[\(offset)...\(offset + limit)]\(summaryProjection)"
    }

    /// Full document for the detail screen.
    static func setupDetail(slug: String) -> String {
        """
        *[_type=="setup" && \(notDraft) && slug.current=="\(escape(slug))"][0]\
        {issueNumber, "slug": slug.current, guestName, guestTitle, guestLocation, publishedAt, \
        photos[]{alt, "url": asset->url}, \
        gear[]{name, category, affiliateUrl, description}, \
        qa[]{question, answer}, \
        guestBio, \
        guestLinks[]{platform, url}}
        """
    }

    static let allTags = #"*[_type=="tag"]{name, "slug": slug.current} | order(name asc)"#

    /// Escapes a value for interpolation inside a double-quoted GROQ string literal.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
