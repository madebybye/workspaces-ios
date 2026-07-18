import SwiftUI

// Shared editorial building blocks: paper tone, ink tints, hairline rules,
// kickers, and Dynamic Type–aware font helpers.

// Note: `Color.paper` is auto-generated from Assets.xcassets ("Paper" colorset):
// warm paper white in light mode, near-black in dark mode.

// MARK: - Ink tints

// Secondary/tertiary "ink" grays tuned to pass WCAG AA (>= 4.5:1) on the
// paper background in both appearances. The system hierarchical styles fail
// on paper (secondary ~3.3:1, tertiary ~2.0:1 in light mode), so quiet text
// uses these instead.
extension Color {
    /// ~6.8:1 on light paper, ~7.6:1 on dark paper.
    static let inkSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.651, green: 0.631, blue: 0.604, alpha: 1) // #A6A19A
            : UIColor(red: 0.361, green: 0.345, blue: 0.322, alpha: 1) // #5C5852
    })

    /// ~4.9:1 on light paper, ~5.7:1 on dark paper.
    static let inkTertiary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.561, green: 0.541, blue: 0.514, alpha: 1) // #8F8A83
            : UIColor(red: 0.451, green: 0.427, blue: 0.396, alpha: 1) // #736D65
    })
}

// MARK: - Dynamic Type scaling

/// Applies a system font whose point size scales with the user's Dynamic
/// Type setting, relative to a given text style's growth curve.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))`, but the size tracks Dynamic Type.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: style))
    }
}

// MARK: - Rules & kickers

/// A 0.5pt hairline rule.
struct Hairline: View {
    var opacity: Double = 0.22

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(opacity))
            .frame(height: 0.5)
    }
}

/// The ink hierarchy a `Kicker` can be printed in. Secondary and tertiary
/// map to the contrast-checked ink tints rather than the system styles.
enum InkTone {
    case primary
    case secondary
    case tertiary

    var style: AnyShapeStyle {
        switch self {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(Color.inkSecondary)
        case .tertiary: AnyShapeStyle(Color.inkTertiary)
        }
    }
}

/// Small, uppercase, letterspaced metadata line — the magazine "kicker".
/// The size scales with Dynamic Type (footnote curve); tracking stays fixed.
struct Kicker: View {
    let text: String
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 11
    private let baseSize: CGFloat
    var color: InkTone = .secondary

    init(_ text: String, size: CGFloat = 11, color: InkTone = .secondary) {
        self.text = text
        self.baseSize = size
        _size = ScaledMetric(wrappedValue: size, relativeTo: .footnote)
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .kerning(baseSize * 0.14)
            .foregroundStyle(color.style)
            .fixedSize(horizontal: false, vertical: true)
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
        guard !tags.isEmpty else { return nil }
        return tags.map(\.name).joined(separator: " / ")
    }

    /// One spoken line for VoiceOver: "Issue 536, Zack Davenport, Founding
    /// Product and Brand Designer, New York".
    var accessibilitySummary: String {
        var parts = ["Issue \(issueNumber)", guestName]
        if let guestTitle, !guestTitle.isEmpty { parts.append(guestTitle) }
        if let location = guestLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: ", ")
    }
}
