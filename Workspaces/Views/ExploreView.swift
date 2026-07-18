import SwiftUI

/// Search by guest name and/or filter by tag. Results reuse the feed cards
/// and pagination.
struct ExploreView: View {
    @State private var tagStore = TagStore()
    @State private var results = FeedStore()
    @State private var searchText = ""
    @State private var selectedTag: Tag?

    private var isFiltering: Bool {
        selectedTag != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isFiltering {
                    resultsView
                } else {
                    tagBrowser
                }
            }
            .navigationTitle("Explore")
            .navigationDestination(for: SetupSummary.self) { setup in
                SetupDetailView(summary: setup)
            }
            .searchable(text: $searchText, prompt: "Search by guest name")
            .task { await tagStore.load() }
            .onChange(of: searchText) {
                applyFilters()
            }
            .onChange(of: selectedTag) {
                applyFilters()
            }
        }
    }

    private func applyFilters() {
        guard isFiltering else { return }
        results.tagSlug = selectedTag?.slug
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        results.search = trimmed.isEmpty ? nil : trimmed
        Task { await results.reload(showSpinner: true) }
    }

    // MARK: Tag browser (default state)

    private var tagBrowser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Browse by tag")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(.secondary)

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
                    FlowLayout(spacing: 8) {
                        ForEach(tagStore.tags) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                TagChip(name: tag.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            if let tag = selectedTag {
                activeTagBanner(tag)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            switch results.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) {
                    await results.reload(showSpinner: true)
                }
            case .empty:
                ContentUnavailableView.search
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 36) {
                        ForEach(results.setups) { setup in
                            NavigationLink(value: setup) {
                                SetupCard(setup: setup)
                            }
                            .buttonStyle(.plain)
                            .onAppear { results.loadMoreIfNeeded(current: setup) }
                        }
                        if results.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func activeTagBanner(_ tag: Tag) -> some View {
        HStack {
            Button {
                selectedTag = nil
            } label: {
                HStack(spacing: 6) {
                    TagChip(name: tag.name, isSelected: true)
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear tag filter \(tag.name)")
            Spacer()
        }
    }
}

#Preview {
    ExploreView()
}
