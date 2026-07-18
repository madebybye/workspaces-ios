import SwiftUI

/// The front-of-book feed. On compact width (iPhone): a full-bleed lead story
/// followed by entries that alternate between full-width and split layouts,
/// separated by hairlines. On regular width (iPad): the lead story spans the
/// full width and subsequent entries flow into a two-column magazine grid.
struct FeedView: View {
    let store: FeedStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            switch store.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) {
                    await store.reload(showSpinner: true)
                }
            case .empty:
                ContentUnavailableView(
                    "No setups yet",
                    systemImage: "desktopcomputer",
                    description: Text("Check back soon for new workspaces.")
                )
            case .loaded:
                if horizontalSizeClass == .regular {
                    feedGrid
                } else {
                    feedList
                }
            }
        }
        .task { await store.loadInitial() }
    }

    // MARK: Compact (iPhone) — unchanged single column

    private var feedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.setups.enumerated()), id: \.element.id) { index, setup in
                    NavigationLink(value: setup) {
                        FeedEntry(setup: setup, style: style(for: index))
                    }
                    .buttonStyle(.plain)
                    .onAppear { store.loadMoreIfNeeded(current: setup) }

                    if setup.id != store.setups.last?.id {
                        Hairline()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 36)
                    }
                }

                if store.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
        .refreshable { await store.refresh() }
    }

    private func style(for index: Int) -> FeedEntry.Style {
        if index == 0 { return .lead }
        return index.isMultiple(of: 2) ? .split : .full
    }

    // MARK: Regular (iPad) — lead + two-column magazine grid

    private var feedGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let lead = store.setups.first {
                    NavigationLink(value: lead) {
                        FeedEntry(setup: lead, style: .lead)
                    }
                    .buttonStyle(.plain)
                    .onAppear { store.loadMoreIfNeeded(current: lead) }

                    Hairline()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 40)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 36, alignment: .top),
                        GridItem(.flexible(), alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: 44
                ) {
                    ForEach(store.setups.dropFirst()) { setup in
                        NavigationLink(value: setup) {
                            FeedEntry(setup: setup, style: .full)
                        }
                        .buttonStyle(.plain)
                        .onAppear { store.loadMoreIfNeeded(current: setup) }
                    }
                }
                .padding(.horizontal, 24)

                if store.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
        .refreshable { await store.refresh() }
    }
}

/// One feed entry in one of three editorial layouts. Reads as a single
/// VoiceOver element ("Issue 536, Zack Davenport, Founding Product and Brand
/// Designer, New York") instead of fragmenting into kicker/name/dek/tags.
/// At accessibility text sizes the split layout falls back to the full-width
/// layout so the two-column row never overlaps.
struct FeedEntry: View {
    enum Style {
        case lead   // oversized: full-bleed photo, headline-scale name
        case full   // full-bleed photo, standard text block
        case split  // text + oversized numeral beside a trailing-bleed photo
    }

    let setup: SetupSummary
    var style: Style = .full
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch style {
            case .lead: leadLayout
            case .full: fullLayout
            case .split:
                if dynamicTypeSize.isAccessibilitySize {
                    fullLayout
                } else {
                    splitLayout
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(setup.accessibilitySummary)
    }

    // MARK: Lead story

    private var leadLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(width: 1200, aspectRatio: 4 / 3)

            VStack(alignment: .leading, spacing: 10) {
                Kicker(setup.kickerLine)
                    .padding(.top, 18)

                Text(setup.guestName)
                    .scaledFont(size: 36, weight: .bold, design: .serif, relativeTo: .largeTitle)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .scaledFont(size: 17, design: .serif, relativeTo: .body)
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tagLine = setup.tagLine {
                    Kicker(tagLine, size: 10, color: .tertiary)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
    }

    // MARK: Full-width entry

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(width: 1200, aspectRatio: 3 / 2)

            VStack(alignment: .leading, spacing: 8) {
                Kicker(setup.kickerLine, size: 10)
                    .padding(.top, 16)

                Text(setup.guestName)
                    .scaledFont(size: 25, weight: .semibold, design: .serif, relativeTo: .title2)
                    .fixedSize(horizontal: false, vertical: true)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .scaledFont(size: 15, design: .serif, relativeTo: .subheadline)
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tagLine = setup.tagLine {
                    Kicker(tagLine, size: 9, color: .tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
    }

    // MARK: Split entry (folio numeral + trailing-bleed photo)

    private var splitLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(setup.issueNumber)")
                    .scaledFont(size: 64, weight: .thin, design: .serif, relativeTo: .largeTitle)
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.bottom, 2)

                if let date = setup.publishedAt {
                    Kicker(date.dateline, size: 9)
                }

                Text(setup.guestName)
                    .scaledFont(size: 21, weight: .semibold, design: .serif, relativeTo: .title3)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .scaledFont(size: 14, design: .serif, relativeTo: .footnote)
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tagLine = setup.tagLine {
                    Kicker(tagLine, size: 9, color: .tertiary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            photo(width: 600, aspectRatio: 3 / 4)
                .frame(width: 185)
        }
        .padding(.leading, 20)
        .contentShape(Rectangle())
    }

    /// The hero photo cropped to a fixed aspect ratio. `Color.clear` (which
    /// has no intrinsic size) owns the layout and the image is only an
    /// overlay, so the cell strictly respects the width its column proposes —
    /// a `.fill` image sized by its own aspect ratio would otherwise report a
    /// wider ideal width and push the whole cell off its column (the iPad
    /// landscape grid bug). Widths stay in the prefetch's canonical set
    /// {1200, 600, 300} so tier-1-synced issues render offline with no
    /// duplicate downloads.
    private func photo(width: Int, aspectRatio: CGFloat) -> some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { RemoteImage(url: setup.hero?.url(width: width)) }
            .clipped()
            .accessibilityLabel(setup.hero?.alt ?? "Workspace photo of \(setup.guestName)")
    }
}

/// A reusable failure state with retry.
struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Kicker("Something went wrong")
            Text(message)
                .scaledFont(size: 15, design: .serif, relativeTo: .subheadline)
                .italic()
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await retry() }
            } label: {
                Text("TRY AGAIN")
                    .scaledFont(size: 12, weight: .bold, relativeTo: .footnote)
                    .kerning(1.8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().stroke(.primary, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
