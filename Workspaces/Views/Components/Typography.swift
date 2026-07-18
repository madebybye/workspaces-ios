import SwiftUI

// Shared editorial building blocks: paper tone, hairline rules, kickers.

// Note: `Color.paper` is auto-generated from Assets.xcassets ("Paper" colorset):
// warm paper white in light mode, near-black in dark mode.

/// A 0.5pt hairline rule.
struct Hairline: View {
    var opacity: Double = 0.22

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(opacity))
            .frame(height: 0.5)
    }
}

/// Small, uppercase, letterspaced metadata line — the magazine "kicker".
struct Kicker: View {
    let text: String
    var size: CGFloat = 11
    var color: HierarchicalShapeStyle = .secondary

    init(_ text: String, size: CGFloat = 11, color: HierarchicalShapeStyle = .secondary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .kerning(size * 0.14)
            .foregroundStyle(color)
    }
}

/// Tracked-uppercase section header with a hairline above ("GEAR", "Q&A"…).
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Hairline()
            Kicker(title, size: 12, color: .primary)
        }
    }
}

extension Date {
    /// "18 JUL 2026" style dateline (uppercased by Kicker).
    var dateline: String {
        formatted(.dateTime.day().month(.abbreviated).year())
    }
}

extension SetupSummary {
    /// "ISSUE 536 · 18 JUL 2026" (+ location when present).
    var kickerLine: String {
        var parts = ["Issue \(issueNumber)"]
        if let publishedAt { parts.append(publishedAt.dateline) }
        if let location = guestLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: "  ·  ")
    }

    /// "HOME OFFICE / LIGHT-FILLED / DESIGNER" quiet inline tag line.
    var tagLine: String? {
        guard let tags, !tags.isEmpty else { return nil }
        return tags.map(\.name).joined(separator: " / ")
    }
}
