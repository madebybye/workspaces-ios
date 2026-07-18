import SwiftUI

@main
struct WorkspacesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await NotificationScheduler.scheduleWeeklyIssueReminder() }
        }
    }
}

struct RootView: View {
    enum Section {
        case latest
        case saved
        case collections
        case index
    }

    @State private var section: Section = .latest
    @State private var path = NavigationPath()

    // Stores live here so state survives switching sections.
    @State private var feed = FeedStore()
    @State private var savedStore = SavedStore()
    @State private var tagStore = TagStore()
    @State private var collectionStore = CollectionStore()
    @State private var gearIndex = GearIndexStore()
    @State private var results = FeedStore()
    @State private var searchText = ""
    @State private var selectedTag: Tag?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Masthead(section: $section)

                switch section {
                case .latest:
                    FeedView(store: feed)
                case .saved:
                    SavedView(store: savedStore)
                case .collections:
                    CollectionsView(store: collectionStore)
                case .index:
                    IndexView(
                        tagStore: tagStore,
                        gearIndex: gearIndex,
                        results: results,
                        searchText: $searchText,
                        selectedTag: $selectedTag
                    )
                }
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SetupSummary.self) { setup in
                SetupDetailView(summary: setup, saved: savedStore)
            }
            .navigationDestination(for: GearRef.self) { gear in
                GearResultsView(gear: gear)
            }
            .navigationDestination(for: SetupCollection.self) { collection in
                CollectionResultsView(collection: collection)
            }
        }
        .tint(.primary)
    }
}

/// The magazine masthead: nameplate, dateline, hairlines, section switcher.
/// At accessibility text sizes the nameplate row and the three-item switcher
/// stack vertically so nothing truncates or overlaps.
private struct Masthead: View {
    @Binding var section: RootView.Section
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            nameplate
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 10)

            Hairline(opacity: 0.6)
                .padding(.horizontal, 20)

            switcher
                .padding(.horizontal, 20)

            Hairline()
        }
        .background(Color.paper)
    }

    @ViewBuilder
    private var nameplate: some View {
        let title = Text("WORKSPACES")
            .scaledFont(size: 28, weight: .black, design: .serif, relativeTo: .title)
            .kerning(1.0)
        let dateline = Kicker(Date.now.dateline, size: 10, color: .tertiary)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                title
                dateline
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                title
                Spacer()
                dateline
            }
        }
    }

    @ViewBuilder
    private var switcher: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                sectionButton("Latest", .latest)
                sectionButton("Saved", .saved)
                sectionButton("Collections", .collections)
                sectionButton("Index", .index)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Four items: tighter tracking and gaps than the old three-item
            // row so LATEST/SAVED/COLLECTIONS/INDEX fits compact widths.
            HStack(spacing: 18) {
                sectionButton("Latest", .latest)
                sectionButton("Saved", .saved)
                sectionButton("Collections", .collections)
                sectionButton("Index", .index)
                Spacer(minLength: 0)
            }
        }
    }

    private func sectionButton(_ title: String, _ value: RootView.Section) -> some View {
        Button {
            section = value
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .scaledFont(size: 11.5, weight: section == value ? .bold : .medium, relativeTo: .footnote)
                    .kerning(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(section == value ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.inkSecondary))
                    .padding(.vertical, 12)
                Rectangle()
                    .fill(section == value ? Color.primary : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) section")
        .accessibilityAddTraits(section == value ? .isSelected : [])
    }
}

#Preview {
    RootView()
}
