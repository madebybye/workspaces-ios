import SwiftUI

/// The back-of-book index: minimal search, a typographic two-column tag
/// index, and compact hairline-ruled result rows.
struct IndexView: View {
    let tagStore: TagStore
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
                resultsList
            } else {
                tagIndex
            }
        }
        .task { await tagStore.load() }
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

    // MARK: Tag index (default state)

    private var tagIndex: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Kicker("Filed under", size: 10, color: .tertiary)
                    .padding(.top, 16)

                switch tagStore.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                case .failed(let message):
                    ErrorStateView(message: message) {
                        await tagStore.load()
                    }
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
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
    }

    // MARK: Results

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

    private var resultsList: some View {
        Group {
            switch results.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) {
                    await results.reload(showSpinner: true)
                }
            case .empty:
                VStack(spacing: 12) {
                    Kicker("No results")
                    Text("Nothing filed under this yet.")
                        .font(.system(size: 15, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results.setups) { setup in
                            NavigationLink(value: setup) {
                                IndexResultRow(setup: setup)
                            }
                            .buttonStyle(.plain)
                            .onAppear { results.loadMoreIfNeeded(current: setup) }

                            if setup.id != results.setups.last?.id {
                                Hairline(opacity: 0.12)
                                    .padding(.leading, 20)
                            }
                        }
                        if results.isLoadingMore {
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
}

/// A compact, text-led result row with a small square thumbnail.
private struct IndexResultRow: View {
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
