import SwiftUI

/// The back-of-book index: minimal search, then TAGS / COLLECTIONS / GEAR as
/// hairline-ruled typographic sections, and compact result rows when
/// filtering.
struct IndexView: View {
    let tagStore: TagStore
    let collectionStore: CollectionStore
    let gearIndex: GearIndexStore
    let results: FeedStore
    @Binding var searchText: String
    @Binding var selectedTag: Tag?

    private var isFiltering: Bool {
        selectedTag != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if isFiltering {
                filterBanner
                SetupResultsList(store: results)
            } else {
                browseIndex
            }
        }
        .task {
            await tagStore.load()
            await collectionStore.load()
            await gearIndex.load()
        }
        .onChange(of: searchText) { applyFilters() }
        .onChange(of: selectedTag) { applyFilters() }
    }

    private func applyFilters() {
        guard isFiltering else { return }
        results.tagSlug = selectedTag?.slug
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        results.search = trimmed.isEmpty ? nil : trimmed
        Task { await results.reload(showSpinner: true) }
    }

    // MARK: Search

    private var searchField: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("SEARCH BY GUEST NAME")
                        .font(.system(size: 12, weight: .medium))
                        .kerning(1.5)
                        .foregroundStyle(.tertiary)
                )
                .font(.system(size: 15, design: .serif))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 40) {
                tagsSection
                collectionsSection
                gearSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .refreshable {
            await gearIndex.refresh()
            await collectionStore.load(forceFresh: true)
        }
    }

    /// Compact inline retry line for a failed section, so one dead section
    /// doesn't take over the whole index.
    private func sectionRetry(_ retry: @escaping () async -> Void) -> some View {
        Button {
            Task { await retry() }
        } label: {
            Text("Couldn't load — tap to retry.")
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
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

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Tags")

            switch tagStore.phase {
            case .loading:
                sectionSpinner
            case .failed:
                sectionRetry { await tagStore.load() }
            case .loaded:
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(tagStore.tags) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(tag.name.uppercased())
                                    .font(.system(size: 12, weight: .medium))
                                    .kerning(1.5)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.vertical, 13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Hairline(opacity: 0.12)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Collections

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Collections")

            switch collectionStore.phase {
            case .loading:
                sectionSpinner
            case .failed:
                sectionRetry { await collectionStore.load() }
            case .loaded:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(collectionStore.collections) { collection in
                        NavigationLink(value: collection) {
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(collection.title.uppercased())
                                            .font(.system(size: 12, weight: .medium))
                                            .kerning(1.5)
                                        Spacer()
                                        if let count = collection.setupCount, count > 0 {
                                            Kicker("\(count)", size: 10, color: .tertiary)
                                                .monospacedDigit()
                                        }
                                    }
                                    if let description = collection.description, !description.isEmpty {
                                        Text(description)
                                            .font(.system(size: 13, design: .serif))
                                            .italic()
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Hairline(opacity: 0.12)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                                        .font(.system(size: 12, weight: .medium))
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
                            .foregroundStyle(.secondary)
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
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
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
/// the index results, gear/collection results, and the SAVED list.
struct IndexResultRow: View {
    let setup: SetupSummary

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Kicker("Issue \(setup.issueNumber)", size: 9, color: .tertiary)

                Text(setup.guestName)
                    .font(.system(size: 19, weight: .semibold, design: .serif))

                if let title = setup.guestTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
    }
}
