import Foundation

// MARK: - Lossy decoding

/// An array that drops elements that fail to decode instead of failing the
/// whole document. Live CMS content is occasionally malformed (a gear item
/// without a name, a link without a URL); one bad element should never take
/// down an entire setup. Encodes back to a plain JSON array, so it is
/// invisible to the disk caches.
@propertyWrapper
struct LossyArray<Element: Codable & Hashable>: Codable, Hashable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element] = []) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var result: [Element] = []
        if var container = try? decoder.unkeyedContainer() {
            while !container.isAtEnd {
                if let element = try? container.decode(Element.self) {
                    result.append(element)
                } else {
                    // Consume and discard the malformed element.
                    _ = try? container.decode(DiscardedValue.self)
                }
            }
        }
        wrappedValue = result
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension KeyedDecodingContainer {
    /// A missing key or JSON null decodes as an empty lossy array.
    func decode<T>(_ type: LossyArray<T>.Type, forKey key: Key) throws -> LossyArray<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? LossyArray()
    }
}

/// Decodes successfully from any JSON value and throws it away, advancing
/// an unkeyed container past unrecognized elements.
struct DiscardedValue: Codable {
    init() {}
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

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

    /// Tolerant: only the URL is essential; a malformed `alt` is dropped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        alt = (try? container.decodeIfPresent(String.self, forKey: .alt)) ?? nil
    }

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
    @LossyArray var tags: [Tag]

    var id: String { slug }

    /// Tolerant: only identity fields are essential. Anything else that is
    /// missing, null, or malformed degrades to nil / empty instead of
    /// failing the whole summary (and with it the entire feed page).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issueNumber = try c.decode(Int.self, forKey: .issueNumber)
        slug = try c.decode(String.self, forKey: .slug)
        guestName = try c.decode(String.self, forKey: .guestName)
        guestTitle = (try? c.decodeIfPresent(String.self, forKey: .guestTitle)) ?? nil
        guestLocation = (try? c.decodeIfPresent(String.self, forKey: .guestLocation)) ?? nil
        publishedAt = (try? c.decodeIfPresent(Date.self, forKey: .publishedAt)) ?? nil
        hero = (try? c.decodeIfPresent(Photo.self, forKey: .hero)) ?? nil
        photoCount = (try? c.decodeIfPresent(Int.self, forKey: .photoCount)) ?? nil
        _tags = try c.decode(LossyArray<Tag>.self, forKey: .tags)
    }
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
    @LossyArray var photos: [Photo]
    @LossyArray var gear: [GearItem]
    @LossyArray var qa: [QAItem]
    var guestBio: PortableText?
    @LossyArray var guestLinks: [GuestLink]

    var shareURL: URL { URL(string: "https://workspaces.xyz/p/\(slug)")! }

    /// Tolerant: only identity fields are essential; everything else
    /// degrades to nil / empty, and malformed array elements are dropped
    /// individually via `LossyArray` instead of failing the whole document.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issueNumber = try c.decode(Int.self, forKey: .issueNumber)
        slug = try c.decode(String.self, forKey: .slug)
        guestName = try c.decode(String.self, forKey: .guestName)
        guestTitle = (try? c.decodeIfPresent(String.self, forKey: .guestTitle)) ?? nil
        guestLocation = (try? c.decodeIfPresent(String.self, forKey: .guestLocation)) ?? nil
        publishedAt = (try? c.decodeIfPresent(Date.self, forKey: .publishedAt)) ?? nil
        _photos = try c.decode(LossyArray<Photo>.self, forKey: .photos)
        _gear = try c.decode(LossyArray<GearItem>.self, forKey: .gear)
        _qa = try c.decode(LossyArray<QAItem>.self, forKey: .qa)
        guestBio = (try? c.decodeIfPresent(PortableText.self, forKey: .guestBio)) ?? nil
        _guestLinks = try c.decode(LossyArray<GuestLink>.self, forKey: .guestLinks)
    }
}

struct GearItem: Codable, Identifiable, Hashable {
    let name: String
    var category: String?
    var affiliateUrl: URL?
    var description: String?

    /// Positionally unique identity, regenerated on every decode. Real CMS
    /// documents repeat the same gear entry verbatim, so any content-derived
    /// id produces duplicate `ForEach` ids and undefined SwiftUI rendering.
    /// Excluded from coding (regenerated when the disk caches are read back)
    /// and from equality/hashing (so cache-vs-fresh change detection still
    /// compares content, not identity).
    let id: UUID

    private enum CodingKeys: String, CodingKey {
        case name, category, affiliateUrl, description
    }

    /// Tolerant: only the name is essential. In particular a malformed
    /// `affiliateUrl` (issue 230 has "http://JBL Tune 600BTNC") must not
    /// drop the gear item, let alone the setup.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? nil
        affiliateUrl = (try? container.decodeIfPresent(URL.self, forKey: .affiliateUrl)) ?? nil
        description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        id = UUID()
    }

    static func == (lhs: GearItem, rhs: GearItem) -> Bool {
        lhs.name == rhs.name
            && lhs.category == rhs.category
            && lhs.affiliateUrl == rhs.affiliateUrl
            && lhs.description == rhs.description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(category)
        hasher.combine(affiliateUrl)
        hasher.combine(description)
    }
}

struct QAItem: Codable, Identifiable, Hashable {
    let question: String
    var answer: PortableText?

    /// Positionally unique identity, regenerated on every decode. 13 real
    /// issues repeat a question with a *different* answer (e.g.
    /// 232-mark-phillips has "What is on your desk?" twice), so a
    /// question-derived id produces duplicate `ForEach` ids and wrong answers
    /// on screen. Excluded from coding and from equality/hashing (see
    /// `GearItem.id`).
    let id: UUID

    private enum CodingKeys: String, CodingKey {
        case question, answer
    }

    /// Tolerant: only the question is essential; an unreadable answer
    /// degrades to nil.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decode(String.self, forKey: .question)
        answer = (try? container.decodeIfPresent(PortableText.self, forKey: .answer)) ?? nil
        id = UUID()
    }

    static func == (lhs: QAItem, rhs: QAItem) -> Bool {
        lhs.question == rhs.question && lhs.answer == rhs.answer
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(question)
        hasher.combine(answer)
    }
}

struct GuestLink: Codable, Identifiable, Hashable {
    var platform: String?
    let url: URL

    var id: String { url.absoluteString }

    /// Tolerant: only the URL is essential; a malformed platform is dropped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        platform = (try? container.decodeIfPresent(String.self, forKey: .platform)) ?? nil
    }
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
        // The CMS delivers rich text in two shapes: proper Portable Text
        // (an array of blocks) and — for some issues, e.g. 532/533 — a bare
        // HTML string. Accept both; anything else degrades to empty.
        if var container = try? decoder.unkeyedContainer() {
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
        } else if let string = try? decoder.singleValueContainer().decode(String.self) {
            blocks = Self.blocks(fromHTML: string)
        } else {
            blocks = []
        }
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

    // MARK: HTML-string fallback

    /// Converts a bare HTML/plain string into paragraphs, preserving anchor
    /// tags as tappable link spans, stripping any other markup, and
    /// unescaping common entities. Best-effort by design: the goal is
    /// readable editorial copy, not full HTML fidelity.
    private static func blocks(fromHTML html: String) -> [Block] {
        let paragraphBreaks = try? NSRegularExpression(
            pattern: #"(?i)</p>|<p\b[^>]*>|<br\s*/?>|\n{2,}"#
        )
        let source = paragraphBreaks?.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: "\n\n"
        ) ?? html

        return source
            .components(separatedBy: "\n\n")
            .compactMap { block(fromHTMLParagraph: $0) }
    }

    /// One paragraph: anchors become link spans (with a markDef carrying the
    /// href), everything between them becomes plain spans.
    private static func block(fromHTMLParagraph paragraph: String) -> Block? {
        guard let anchor = try? NSRegularExpression(
            pattern: #"(?is)<a\b[^>]*\bhref\s*=\s*"([^"]*)"[^>]*>(.*?)</a>"#
        ) else { return nil }

        var children: [Span] = []
        var markDefs: [MarkDef] = []
        var cursor = paragraph.startIndex

        let matches = anchor.matches(
            in: paragraph,
            range: NSRange(paragraph.startIndex..., in: paragraph)
        )
        for (index, match) in matches.enumerated() {
            guard let whole = Range(match.range, in: paragraph),
                  let hrefRange = Range(match.range(at: 1), in: paragraph),
                  let labelRange = Range(match.range(at: 2), in: paragraph)
            else { continue }

            let before = plainText(fromHTML: String(paragraph[cursor..<whole.lowerBound]))
            if !before.isEmpty { children.append(Span(text: before)) }

            let label = plainText(fromHTML: String(paragraph[labelRange]))
            let href = unescapeEntities(String(paragraph[hrefRange]))
            if !label.isEmpty {
                if let url = URL(string: href) {
                    let key = "html-link-\(index)"
                    markDefs.append(MarkDef(_key: key, _type: "link", href: url.absoluteString))
                    children.append(Span(text: label, marks: [key]))
                } else {
                    children.append(Span(text: label))
                }
            }
            cursor = whole.upperBound
        }

        let trailing = plainText(fromHTML: String(paragraph[cursor...]))
        if !trailing.isEmpty { children.append(Span(text: trailing)) }

        let block = Block(_type: "block", children: children, markDefs: markDefs)
        guard !block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return block
    }

    /// Strips any remaining tags and unescapes entities.
    private static func plainText(fromHTML fragment: String) -> String {
        let stripped = (try? NSRegularExpression(pattern: "<[^>]+>"))?
            .stringByReplacingMatches(
                in: fragment,
                range: NSRange(fragment.startIndex..., in: fragment),
                withTemplate: ""
            ) ?? fragment
        return unescapeEntities(stripped)
    }

    private static func unescapeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = string
        for (entity, replacement) in [
            ("&nbsp;", "\u{00A0}"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
