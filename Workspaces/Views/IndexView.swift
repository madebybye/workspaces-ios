import SwiftUI

/// The back-of-book index: minimal search, then TAGS / GEAR as hairline-ruled
/// typographic sections, and compact result rows when filtering. (Collections
/// moved to their own top-level COLLECTIONS section.) On regular width (iPad)
/// the browse sections flow into two columns; at accessibility text sizes the
/// tag grid collapses to one column.
struct IndexView: View {
    let tagStore: TagStore
    let gearIndex: GearIndexStore
    let results: FeedStore
    @Binding var searchText: String
    @Binding var selectedTag: Tag?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var promptSize: CGFloat = 12

    @State private var searchDebounceTask: Task<Void, Never>?

    private var isFiltering: Bool {
        selectedTag != nil || isSearching
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if isFiltering {
                filterBanner
                SetupResultsList(
                    store: results,
                    emptyText: isSearching ? "No results." : "Nothing filed under this yet."
                )
            } else {
                browseIndex
            }
        }
        .task {
            await tagStore.load()
            await gearIndex.load()
        }
        .onChange(of: searchText) { debouncedApplyFilters() }
        .onChange(of: selectedTag) { applyFilters() }
    }

    /// Keystrokes are debounced ~300 ms so we query once per pause, not once
    /// per character. Tag selection still applies immediately.
    private func debouncedApplyFilters() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            applyFilters()
        }
    }

    private func applyFilters() {
        guard isFiltering else { return }
        results.tagSlug = selectedTag?.slug
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        results.search = trimmed.isEmpty ? nil : trimmed
        // Keep the previous results on screen while the new query runs; the
        // spinner only shows when there is nothing to keep showing.
        Task { await results.reload(showSpinner: results.setups.isEmpty) }
    }

    // MARK: Search

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("SEARCH BY GUEST NAME")
                        .font(.system(size: promptSize, weight: .medium))
                        .kerning(1.5)
                        .foregroundStyle(Color.inkTertiary)
                )
                .scaledFont(size: 15, design: .serif, relativeTo: .body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search by guest name")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            Hairline(opacity: 0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: Browse index (default state)

    private var browseIndex: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 48) {
                        tagsSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        gearSection
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 40) {
                        tagsSection
                        gearSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            colophon
                .padding(.horizontal, 20)
                .padding(.top, 48)
                .padding(.bottom, 48)
        }
        .refreshable {
            await gearIndex.refresh()
        }
    }

    /// Unobtrusive colophon: unofficial-companion note and the affiliate
    /// disclosure App Store review expects.
    private var colophon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Hairline()
            Kicker("About", size: 9, color: .tertiary)
            Text("An unofficial companion to workspaces.xyz. Gear links may be affiliate links.")
                .scaledFont(size: 12, design: .serif, relativeTo: .caption)
                .italic()
                .foregroundStyle(Color.inkSecondary)
                .lineSpacing(3)
        }
        .accessibilityElement(children: .combine)
    }

    /// Compact inline retry line for a failed section, so one dead section
    /// doesn't take over the whole index.
    private func sectionRetry(_ retry: @escaping () async -> Void) -> some View {
        Button {
            Task { await retry() }
        } label: {
            Text("Couldn't load — tap to retry.")
                .scaledFont(size: 14, design: .serif, relativeTo: .footnote)
                .italic()
                .foregroundStyle(Color.inkSecondary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private var sectionSpinner: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: Tags

    private var tagColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible(), spacing: 24), GridItem(.flexible())]
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Tags")

            switch tagStore.phase {
            case .loading:
                sectionSpinner
            case .failed:
                sectionRetry { await tagStore.load() }
            case .loaded:
                LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 0) {
                    ForEach(tagStore.tags) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(tag.name.uppercased())
                                    .scaledFont(size: 12, weight: .medium, relativeTo: .footnote)
                                    .kerning(1.5)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.vertical, 13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Hairline(opacity: 0.12)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tag.name), tag")
                        .accessibilityHint("Shows setups filed under this tag")
                    }
                }
            }
        }
    }

    // MARK: Gear

    private var gearSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Gear")

            switch gearIndex.phase {
            case .loading:
                sectionSpinner
            case .failed:
                sectionRetry { await gearIndex.retry() }
            case .loaded:
                VStack(alignment: .leading, spacing: 0) {
                    Kicker("Most featured", size: 9, color: .tertiary)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    ForEach(gearIndex.entries) { entry in
                        NavigationLink(value: GearRef(name: entry.name)) {
                            VStack(spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(entry.name.uppercased())
                                        .scaledFont(size: 12, weight: .medium, relativeTo: .footnote)
                                        .kerning(1.5)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer()
                                    Kicker(
                                        "\(entry.setupCount) \(entry.setupCount == 1 ? "setup" : "setups")",
                                        size: 9,
                                        color: .tertiary
                                    )
                                    .monospacedDigit()
                                }
                                .padding(.vertical, 13)
                                Hairline(opacity: 0.12)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(entry.name), featured in \(entry.setupCount) \(entry.setupCount == 1 ? "setup" : "setups")"
                        )
                    }
                }
            }
        }
    }

    // MARK: Filtered results

    private var filterBanner: some View {
        VStack(spacing: 0) {
            if let tag = selectedTag {
                HStack(spacing: 8) {
                    Kicker("Filed under — \(tag.name)", size: 10)
                    Button {
                        selectedTag = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear tag filter \(tag.name)")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Hairline()
            }
        }
    }
}

/// A phase-aware, paginated list of compact result rows. Shared by the index
/// search/tag results and the gear and collection screens.
struct SetupResultsList: View {
    let store: FeedStore
    var emptyText = "Nothing filed under this yet."

    var body: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ErrorStateView(message: message) {
                await store.reload(showSpinner: true)
            }
        case .empty:
            VStack(spacing: 12) {
                Kicker("No results")
                Text(emptyText)
                    .scaledFont(size: 15, design: .serif, relativeTo: .subheadline)
                    .italic()
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.setups) { setup in
                        NavigationLink(value: setup) {
                            IndexResultRow(setup: setup)
                        }
                        .buttonStyle(.plain)
                        .onAppear { store.loadMoreIfNeeded(current: setup) }

                        if setup.id != store.setups.last?.id {
                            Hairline(opacity: 0.12)
                                .padding(.leading, 20)
                        }
                    }
                    if store.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}

/// A compact, text-led result row with a small square thumbnail. Shared by
/// the index results, gear/collection results, and the SAVED list. Reads as
/// one VoiceOver element per setup.
struct IndexResultRow: View {
    let setup: SetupSummary

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Kicker("Issue \(setup.issueNumber)", size: 9, color: .tertiary)

                Text(setup.guestName)
                    .scaledFont(size: 19, weight: .semibold, design: .serif, relativeTo: .title3)

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .scaledFont(size: 13, design: .serif, relativeTo: .footnote)
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RemoteImage(url: setup.hero?.url(width: 300))
                .frame(width: 84, height: 84)
                .clipped()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(setup.accessibilitySummary)
    }
}
