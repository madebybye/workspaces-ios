import Foundation

// MARK: - Shared models

/// A tag document, e.g. { name: "Home Office", slug: "home-office" }.
/// Codable (not just Decodable) so it can round-trip through the feed disk cache.
struct Tag: Codable, Identifiable, Hashable {
    let name: String
    let slug: String

    var id: String { slug }
}

/// A photo with a Sanity CDN URL. Widths are applied server-side via query params.
struct Photo: Codable, Hashable {
    var alt: String?
    let url: URL

    /// Returns a CDN URL resized server-side to the given pixel width.
    func url(width: Int) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "w", value: String(width)),
            URLQueryItem(name: "auto", value: "format"),
            URLQueryItem(name: "q", value: "80"),
        ]
        return components?.url ?? url
    }
}

// MARK: - Feed

/// A setup as it appears in the feed list.
/// Codable (not just Decodable) so it can round-trip through the feed disk cache.
struct SetupSummary: Codable, Identifiable, Hashable {
    let issueNumber: Int
    let slug: String
    let guestName: String
    var guestTitle: String?
    var guestLocation: String?
    var publishedAt: Date?
    var hero: Photo?
    var photoCount: Int?
    var tags: [Tag]?

    var id: String { slug }
}

// MARK: - Detail

struct SetupDetail: Decodable {
    let issueNumber: Int
    let slug: String
    let guestName: String
    var guestTitle: String?
    var guestLocation: String?
    var publishedAt: Date?
    var photos: [Photo]?
    var gear: [GearItem]?
    var qa: [QAItem]?
    var guestBio: PortableText?
    var guestLinks: [GuestLink]?

    var shareURL: URL { URL(string: "https://workspaces.xyz/p/\(slug)")! }
}

struct GearItem: Decodable, Identifiable, Hashable {
    let name: String
    var category: String?
    var affiliateUrl: URL?
    var description: String?

    var id: String { (category ?? "") + name + (affiliateUrl?.absoluteString ?? "") }
}

struct QAItem: Decodable, Identifiable, Hashable {
    let question: String
    var answer: PortableText?

    var id: String { question }
}

struct GuestLink: Decodable, Identifiable, Hashable {
    var platform: String?
    let url: URL

    var id: String { url.absoluteString }
}

// MARK: - Portable Text

/// A tolerant flattener for Sanity Portable Text. Unknown block types and
/// malformed elements are skipped; text blocks are flattened to paragraphs.
struct PortableText: Decodable, Hashable {
    let paragraphs: [String]

    var text: String { paragraphs.joined(separator: "\n\n") }
    var isEmpty: Bool { paragraphs.isEmpty }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [String] = []
        while !container.isAtEnd {
            if let block = try? container.decode(Block.self) {
                if block._type == "block" {
                    let text = (block.children ?? [])
                        .compactMap(\.text)
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { result.append(text) }
                }
            } else {
                // Consume and discard anything that is not an object.
                _ = try? container.decode(DiscardedValue.self)
            }
        }
        paragraphs = result
    }

    private struct Block: Decodable {
        var _type: String?
        var children: [Span]?
    }

    private struct Span: Decodable {
        var text: String?
    }

    /// Decodes successfully from any JSON value and throws it away,
    /// advancing the unkeyed container past unrecognized elements.
    private struct DiscardedValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
