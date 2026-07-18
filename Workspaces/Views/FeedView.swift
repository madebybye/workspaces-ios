import SwiftUI

struct FeedView: View {
    @State private var store = FeedStore()

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Workspaces")
            .navigationDestination(for: SetupSummary.self) { setup in
                SetupDetailView(summary: setup)
            }
            .task { await store.loadInitial() }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                ForEach(store.setups) { setup in
                    NavigationLink(value: setup) {
                        SetupCard(setup: setup)
                    }
                    .buttonStyle(.plain)
                    .onAppear { store.loadMoreIfNeeded(current: setup) }
                }

                if store.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await store.refresh() }
    }
}

/// One setup in the feed: hero photo, issue metadata, guest info, tags.
struct SetupCard: View {
    let setup: SetupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: setup.hero?.url(width: 800))
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let count = setup.photoCount, count > 1 {
                        Label("\(count)", systemImage: "photo.stack")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .accessibilityLabel(setup.hero?.alt ?? "Workspace photo of \(setup.guestName)")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Issue \(setup.issueNumber)")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.8)
                    if let date = setup.publishedAt {
                        Text("·")
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)

                Text(setup.guestName)
                    .font(.title3.weight(.semibold))

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let location = setup.guestLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
            }

            if let tags = setup.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        TagChip(name: tag.name)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// A reusable failure state with retry.
struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    FeedView()
}
