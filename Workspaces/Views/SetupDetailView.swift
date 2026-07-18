import SwiftUI

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
        .navigationTitle("Issue \(summary.issueNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://workspaces.xyz/p/\(summary.slug)")!) {
                    Image(systemName: "square.and.arrow.up")
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

                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let bio = detail.guestBio, !bio.isEmpty {
                        Text(bio.text)
                            .font(.callout)
                            .lineSpacing(4)
                            .foregroundStyle(.primary.opacity(0.85))
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Issue \(detail.issueNumber)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                if let date = detail.publishedAt {
                    Text("·")
                    Text(date, format: .dateTime.day().month(.wide).year())
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            Text(detail.guestName)
                .font(.title.weight(.bold))

            if let title = detail.guestTitle, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let location = detail.guestLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func linksRow(_ links: [GuestLink]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    Label(link.platform ?? link.url.host() ?? "Link", systemImage: "arrow.up.right")
                        .font(.footnote.weight(.medium))
                        .labelStyle(TrailingIconLabelStyle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Horizontally paged photo gallery.
private struct PhotoGallery: View {
    let photos: [Photo]
    @State private var page = 0

    var body: some View {
        if photos.isEmpty {
            RemoteImage(url: nil)
                .aspectRatio(4 / 3, contentMode: .fit)
        } else {
            VStack(spacing: 10) {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        RemoteImage(url: photo.url(width: 1200))
                            .accessibilityLabel(photo.alt ?? "Workspace photo \(index + 1)")
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()

                if photos.count > 1 {
                    Text("\(page + 1) / \(photos.count)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Gear list grouped by category.
private struct GearSection: View {
    let gear: [GearItem]

    private var groups: [(category: String, items: [GearItem])] {
        let grouped = Dictionary(grouping: gear) { $0.category ?? "Other" }
        return grouped
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading("Gear")

            ForEach(groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.category)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.8)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.items) { item in
                            GearRow(item: item)
                            if item.id != group.items.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.trimmingCharacters(in: .whitespaces))
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Q&A rendered from flattened portable text.
private struct QASection: View {
    let items: [QAItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading("Q & A")

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.question)
                        .font(.headline)
                    if let answer = item.answer, !answer.isEmpty {
                        Text(answer.text)
                            .font(.callout)
                            .lineSpacing(4)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
        }
    }
}

private struct SectionHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
