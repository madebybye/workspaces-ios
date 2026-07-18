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
                case .index:
                    IndexView(
                        tagStore: tagStore,
                        collectionStore: collectionStore,
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
private struct Masthead: View {
    @Binding var section: RootView.Section

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("WORKSPACES")
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .kerning(1.0)
                Spacer()
                Kicker(Date.now.dateline, size: 10, color: .tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 10)

            Hairline(opacity: 0.6)
                .padding(.horizontal, 20)

            HStack(spacing: 28) {
                sectionButton("Latest", .latest)
                sectionButton("Saved", .saved)
                sectionButton("Index", .index)
                Spacer()
            }
            .padding(.horizontal, 20)

            Hairline()
        }
        .background(Color.paper)
    }

    private func sectionButton(_ title: String, _ value: RootView.Section) -> some View {
        Button {
            section = value
        } label: {
            VStack(spacing: 0) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: section == value ? .bold : .medium))
                    .kerning(1.8)
                    .foregroundStyle(section == value ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .padding(.vertical, 12)
                Rectangle()
                    .fill(section == value ? Color.primary : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == value ? .isSelected : [])
    }
}

#Preview {
    RootView()
}
