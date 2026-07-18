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

// MARK: - Browse dimensions

/// A navigation value for browsing setups by a piece of gear.
struct GearRef: Hashable {
    let name: String
}

/// One row of the most-featured gear index: a display name (first spelling
/// seen), its category, and how many setups feature it. Codable so the
/// aggregation round-trips through its disk cache.
struct GearIndexEntry: Codable, Identifiable, Hashable {
    let name: String
    var category: String?
    let setupCount: Int

    var id: String { name.lowercased() }
}

/// A curated collection document, e.g. { title: "IKEA", slug: "ikea" }.
/// `id` is the Sanity `_id`, which setups reference in their `collections`
/// field; `setupCount` is computed server-side in the projection.
struct SetupCollection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    var description: String?
    var setupCount: Int?
}

// MARK: - Detail

/// Codable (not just Decodable) so it can round-trip through the detail disk
/// cache; Hashable so a background revalidation can detect real changes.
struct SetupDetail: Codable, Hashable {
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

struct GearItem: Codable, Identifiable, Hashable {
    let name: String
    var category: String?
    var affiliateUrl: URL?
    var description: String?

    var id: String { (category ?? "") + name + (affiliateUrl?.absoluteString ?? "") }
}

struct QAItem: Codable, Identifiable, Hashable {
    let question: String
    var answer: PortableText?

    var id: String { question }
}

struct GuestLink: Codable, Identifiable, Hashable {
    var platform: String?
    let url: URL

    var id: String { url.absoluteString }
}

// MARK: - Portable Text

/// A tolerant parser for Sanity Portable Text that keeps enough structure to
/// render marks (bold, italic, links) while degrading gracefully: unknown
/// block types and malformed elements are skipped, unknown marks render as
/// plain text, and `text` remains a plain-string fallback.
///
/// Codable: it re-encodes to the same raw Portable Text shape it decodes
/// from, so it round-trips through the detail disk cache unchanged.
struct PortableText: Codable, Hashable {
    let blocks: [Block]

    /// Plain-text fallback: paragraphs stripped of all marks.
    var paragraphs: [String] { blocks.map(\.plainText) }
    var text: String { paragraphs.joined(separator: "\n\n") }
    var isEmpty: Bool { blocks.isEmpty }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Block] = []
        while !container.isAtEnd {
            if let block = try? container.decode(Block.self) {
                // Keep only real text blocks that have visible content.
                if block._type == "block",
                   !block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(block)
                }
            } else if let string = try? container.decode(String.self),
                      !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A bare string degrades to an unmarked paragraph.
                result.append(Block(_type: "block", children: [Span(text: string)]))
            } else {
                // Consume and discard anything else (numbers, null, arrays…).
                _ = try? container.decode(DiscardedValue.self)
            }
        }
        blocks = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for block in blocks { try container.encode(block) }
    }

    /// One paragraph. `markDefs` carries annotation payloads (e.g. link
    /// hrefs) that spans reference by `_key` in their `marks` array.
    struct Block: Codable, Hashable {
        var _type: String?
        var children: [Span]?
        var markDefs: [MarkDef]?

        var plainText: String {
            (children ?? []).compactMap(\.text).joined()
        }

        /// Resolves a span mark: a decorator string stays as-is, an
        /// annotation key resolves through `markDefs`. Returns nil for
        /// unknown or unresolvable marks so they degrade to plain text.
        func resolve(mark: String) -> ResolvedMark? {
            switch mark {
            case "strong": return .bold
            case "em": return .italic
            case "underline": return .underline
            default:
                guard let def = markDefs?.first(where: { $0._key == mark }) else { return nil }
                if def._type == "link", let href = def.href, let url = URL(string: href) {
                    return .link(url)
                }
                return nil
            }
        }
    }

    struct Span: Codable, Hashable {
        var text: String?
        var marks: [String]?
    }

    struct MarkDef: Codable, Hashable {
        var _key: String?
        var _type: String?
        var href: String?
    }

    enum ResolvedMark: Hashable {
        case bold
        case italic
        case underline
        case link(URL)
    }

    /// Decodes successfully from any JSON value and throws it away,
    /// advancing the unkeyed container past unrecognized elements.
    private struct DiscardedValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
