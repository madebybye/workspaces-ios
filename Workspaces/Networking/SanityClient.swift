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
    /// Pass `forceFresh: true` (e.g. from pull-to-refresh) to bypass any local
    /// HTTP cache for this one request; the default honors protocol caching.
    func fetch<T: Decodable>(_ type: T.Type, query: String, forceFresh: Bool = false) async throws -> T {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        if forceFresh {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let (data, response) = try await session.data(for: request)
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

    /// Feed page, optionally narrowed to a tag, a guest-name prefix search,
    /// a piece of gear (token match on gear names), or a collection (setups
    /// hold direct references to collection documents).
    static func setups(
        offset: Int,
        limit: Int = pageSize,
        tagSlug: String? = nil,
        search: String? = nil,
        gearName: String? = nil,
        collectionId: String? = nil
    ) -> String {
        var filters = [#"_type=="setup""#, notDraft]
        if let tagSlug {
            filters.append("\"\(escape(tagSlug))\" in tags[]->slug.current")
        }
        if let search, !search.isEmpty {
            filters.append("guestName match \"\(escape(search))*\"")
        }
        if let gearName, !gearName.isEmpty {
            filters.append("count(gear[name match \"\(escape(gearName))\"]) > 0")
        }
        if let collectionId {
            filters.append("references(\"\(escape(collectionId))\")")
        }
        let filter = filters.joined(separator: " && ")
        return "*[\(filter)] | order(issueNumber desc)[\(offset)...\(offset + limit)]\(summaryProjection)"
    }

    private static let detailProjection = """
        {issueNumber, "slug": slug.current, guestName, guestTitle, guestLocation, publishedAt, \
        photos[]{alt, "url": asset->url}, \
        gear[]{name, category, affiliateUrl, description}, \
        qa[]{question, answer}, \
        guestBio, \
        guestLinks[]{platform, url}}
        """

    /// Full document for the detail screen.
    static func setupDetail(slug: String) -> String {
        """
        *[_type=="setup" && \(notDraft) && slug.current=="\(escape(slug))"][0]\(detailProjection)
        """
    }

    /// Full documents for a batch of slugs (archive sync; ~50 docs ≈ 300 KB).
    static func setupDetails(slugs: [String]) -> String {
        let list = slugs.map { "\"\(escape($0))\"" }.joined(separator: ",")
        return "*[_type==\"setup\" && \(notDraft) && slug.current in [\(list)]]\(detailProjection)"
    }

    /// Tiny freshness probe for the archive sync: the newest issue number
    /// and the total published count.
    static let archiveHead = """
        {"newest": *[_type=="setup" && \(notDraft)] | order(issueNumber desc)[0].issueNumber, \
        "total": count(*[_type=="setup" && \(notDraft)])}
        """

    /// Every published slug, newest first (~15 KB), for the archive sync.
    static let archiveIndex = """
        *[_type=="setup" && \(notDraft)] | order(issueNumber desc)[].slug.current
        """

    static let allTags = #"*[_type=="tag"]{name, "slug": slug.current} | order(name asc)"#

    /// The nine curated collections with live setup counts. Membership is by
    /// direct reference only — collections also carry a `matchingTags` field,
    /// but it over-matches wildly (hundreds of setups) so it is ignored.
    static let collections = """
        *[_type=="collection"]{"id": _id, title, "slug": slug.current, description, \
        "setupCount": count(*[_type=="setup" && \(notDraft) && references(^._id)])} \
        | order(title asc)
        """

    /// Every published setup's gear names and categories (~420 KB), fetched
    /// once for the client-side most-featured-gear aggregation.
    static let allGear = "*[_type==\"setup\" && \(notDraft)]{gear[]{name, category}}"

    /// Escapes a value for interpolation inside a double-quoted GROQ string literal.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
