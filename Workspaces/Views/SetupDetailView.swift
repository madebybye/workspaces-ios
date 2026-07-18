import SwiftUI

/// A feature spread: full-bleed gallery, serif headline, hairline-ruled
/// sections with tracked-uppercase headers.
struct SetupDetailView: View {
    let summary: SetupSummary
    let saved: SavedStore
    @State private var store: DetailStore

    init(summary: SetupSummary, saved: SavedStore) {
        self.summary = summary
        self.saved = saved
        _store = State(initialValue: DetailStore(slug: summary.slug))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) {
                    await store.retry()
                }
            case .loaded(let detail):
                DetailContent(detail: detail)
            }
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Kicker("Issue \(summary.issueNumber)", size: 11, color: .primary)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    saved.toggle(summary)
                } label: {
                    Image(systemName: saved.isSaved(summary.slug) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .light))
                }
                .accessibilityLabel(
                    saved.isSaved(summary.slug) ? "Remove from saved" : "Save this setup"
                )

                ShareLink(item: URL(string: "https://workspaces.xyz/p/\(summary.slug)")!) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .light))
                }
                .accessibilityLabel("Share this setup")
            }
        }
        .task { await store.load() }
    }
}

private struct DetailContent: View {
    let detail: SetupDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoGallery(photos: detail.photos ?? [])

                VStack(alignment: .leading, spacing: 32) {
                    header

                    if let bio = detail.guestBio, !bio.isEmpty {
                        RichBodyText(content: bio)
                    }

                    if let links = detail.guestLinks, !links.isEmpty {
                        linksRow(links)
                    }

                    if let gear = detail.gear, !gear.isEmpty {
                        GearSection(gear: gear)
                    }

                    if let qa = detail.qa, !qa.isEmpty {
                        QASection(items: qa)
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 56)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(kickerLine)

            Text(detail.guestName)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .lineSpacing(2)

            if let title = detail.guestTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private var kickerLine: String {
        var parts = ["Issue \(detail.issueNumber)"]
        if let date = detail.publishedAt { parts.append(date.dateline) }
        if let location = detail.guestLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: "  ·  ")
    }

    private func linksRow(_ links: [GuestLink]) -> some View {
        FlowLayout(spacing: 20) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    HStack(spacing: 4) {
                        Text((link.platform ?? link.url.host() ?? "Link").uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(1.5)
                            .underline()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Hairline()
            Kicker("workspaces.xyz  ·  Issue \(detail.issueNumber)", size: 9, color: .tertiary)
        }
        .padding(.top, 8)
    }
}

/// Horizontally paged, full-bleed photo gallery.
private struct PhotoGallery: View {
    let photos: [Photo]
    @State private var page = 0

    var body: some View {
        if photos.isEmpty {
            RemoteImage(url: nil)
                .aspectRatio(4 / 3, contentMode: .fit)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        Color.clear
                            .overlay { RemoteImage(url: photo.url(width: 1200)) }
                            .clipped()
                            .accessibilityLabel(photo.alt ?? "Workspace photo \(index + 1)")
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()

                if photos.count > 1 {
                    Kicker("Fig. \(page + 1) / \(photos.count)", size: 9, color: .tertiary)
                        .monospacedDigit()
                        .padding(.trailing, 20)
                }
            }
        }
    }
}

/// Gear grouped by category, text-first with hairline rules.
private struct GearSection: View {
    let gear: [GearItem]

    private var groups: [(category: String, items: [GearItem])] {
        let grouped = Dictionary(grouping: gear) { $0.category ?? "Other" }
        return grouped
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader("Gear")

            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Kicker(group.category, size: 9, color: .tertiary)
                        .padding(.bottom, 8)

                    ForEach(group.items) { item in
                        GearRow(item: item)
                        if item.id != group.items.last?.id {
                            Hairline(opacity: 0.1)
                        }
                    }
                }
            }
        }
    }
}

/// One gear line with two distinct affordances: the name (with a quiet
/// chevron) browses other setups featuring this item in-app; the trailing
/// underlined "SHOP ↗" opens the affiliate link externally.
private struct GearRow: View {
    let item: GearItem

    private var name: String {
        item.name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            NavigationLink(value: GearRef(name: name)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(name)
                            .font(.system(size: 16, design: .serif))
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows other setups featuring this gear")

            if let url = item.affiliateUrl {
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Text("SHOP")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.4)
                            .underline()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shop \(name)")
            }
        }
        .padding(.vertical, 9)
    }
}

/// Portable Text body copy in the editorial serif style: one `Text` per
/// paragraph with bold/italic rendered via font traits and links tappable
/// and underlined. Unknown marks and block types degrade to plain text.
private struct RichBodyText: View {
    let content: PortableText
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: size, design: .serif))
                    .lineSpacing(5.5)
                    .foregroundStyle(.primary.opacity(0.88))
            }
        }
    }

    private var paragraphs: [AttributedString] {
        content.blocks.compactMap { attributedParagraph(for: $0) }
    }

    private func attributedParagraph(for block: PortableText.Block) -> AttributedString? {
        var paragraph = AttributedString()
        for span in block.children ?? [] {
            guard let text = span.text, !text.isEmpty else { continue }
            var run = AttributedString(text)

            var bold = false
            var italic = false
            for mark in span.marks ?? [] {
                // Unresolvable marks return nil and the run stays plain.
                switch block.resolve(mark: mark) {
                case .bold: bold = true
                case .italic: italic = true
                case .underline: run.underlineStyle = .single
                case .link(let url):
                    run.link = url
                    run.underlineStyle = .single
                case nil: break
                }
            }
            if bold || italic {
                var font: Font = .system(size: size, design: .serif)
                if bold { font = font.bold() }
                if italic { font = font.italic() }
                run.font = font
            }
            paragraph.append(run)
        }
        return paragraph.characters.isEmpty ? nil : paragraph
    }
}

/// Q&A: serif bold-italic questions, serif answers.
private struct QASection: View {
    let items: [QAItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SectionHeader("Q & A")

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.question)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .italic()
                        .lineSpacing(3)
                    if let answer = item.answer, !answer.isEmpty {
                        RichBodyText(content: answer)
                    }
                }
            }
        }
    }
}
