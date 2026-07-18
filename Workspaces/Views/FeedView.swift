import SwiftUI

/// The front-of-book feed: a full-bleed lead story followed by entries that
/// alternate between full-width and split layouts, separated by hairlines.
struct FeedView: View {
    let store: FeedStore

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
                feedList
            }
        }
        .task { await store.loadInitial() }
    }

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
}

/// One feed entry in one of three editorial layouts.
struct FeedEntry: View {
    enum Style {
        case lead   // oversized: full-bleed photo, headline-scale name
        case full   // full-bleed photo, standard text block
        case split  // text + oversized numeral beside a trailing-bleed photo
    }

    let setup: SetupSummary
    var style: Style = .full

    var body: some View {
        switch style {
        case .lead: leadLayout
        case .full: fullLayout
        case .split: splitLayout
        }
    }

    // MARK: Lead story

    private var leadLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(width: 1000)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Kicker(setup.kickerLine)
                    .padding(.top, 18)

                Text(setup.guestName)
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .lineSpacing(2)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
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
            photo(width: 900)
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Kicker(setup.kickerLine, size: 10)
                    .padding(.top, 16)

                Text(setup.guestName)
                    .font(.system(size: 25, weight: .semibold, design: .serif))

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
                    .font(.system(size: 64, weight: .thin, design: .serif))
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.bottom, 2)

                if let date = setup.publishedAt {
                    Kicker(date.dateline, size: 9)
                }

                Text(setup.guestName)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .lineSpacing(1)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let tagLine = setup.tagLine {
                    Kicker(tagLine, size: 9, color: .tertiary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            photo(width: 600)
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(width: 185)
                .clipped()
        }
        .padding(.leading, 20)
        .contentShape(Rectangle())
    }

    private func photo(width: Int) -> some View {
        RemoteImage(url: setup.hero?.url(width: width))
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
                .font(.system(size: 15, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await retry() }
            } label: {
                Text("TRY AGAIN")
                    .font(.system(size: 12, weight: .bold))
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
