import SwiftUI

/// A feature spread: full-bleed gallery, serif headline, hairline-ruled
/// sections with tracked-uppercase headers.
struct SetupDetailView: View {
    let summary: SetupSummary
    @State private var store: DetailStore

    init(summary: SetupSummary) {
        self.summary = summary
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
            ToolbarItem(placement: .topBarTrailing) {
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
                        Text(bio.text)
                            .font(.system(size: 15, design: .serif))
                            .lineSpacing(5.5)
                            .foregroundStyle(.primary.opacity(0.88))
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

private struct GearRow: View {
    let item: GearItem

    var body: some View {
        Group {
            if let url = item.affiliateUrl {
                Link(destination: url) { rowContent(linked: true) }
                    .buttonStyle(.plain)
            } else {
                rowContent(linked: false)
            }
        }
    }

    private func rowContent(linked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 16, design: .serif))
                    .multilineTextAlignment(.leading)
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
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
                        Text(answer.text)
                            .font(.system(size: 15, design: .serif))
                            .lineSpacing(5.5)
                            .foregroundStyle(.primary.opacity(0.88))
                    }
                }
            }
        }
    }
}
