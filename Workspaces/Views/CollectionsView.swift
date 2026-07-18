import SwiftUI

/// The COLLECTIONS section: the curated collections as a hairline-ruled
/// typographic list (formerly a section inside INDEX). Rows push the shared
/// `CollectionResultsView`. On regular width (iPad) the list is capped at a
/// readable measure.
struct CollectionsView: View {
    let store: CollectionStore

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorStateView(message: message) {
                    await store.load()
                }
            case .loaded:
                list
            }
        }
        .task { await store.load() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Curated by workspaces.xyz", size: 9, color: .tertiary)
                    .padding(.top, 20)
                    .padding(.bottom, 6)

                ForEach(store.collections) { collection in
                    NavigationLink(value: collection) {
                        CollectionRow(collection: collection)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label(for: collection))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load(forceFresh: true) }
    }

    private func label(for collection: SetupCollection) -> String {
        var parts = ["\(collection.title), collection"]
        if let count = collection.setupCount, count > 0 {
            parts.append("\(count) \(count == 1 ? "setup" : "setups")")
        }
        if let description = collection.description, !description.isEmpty {
            parts.append(description)
        }
        return parts.joined(separator: ", ")
    }
}

/// One collection line: tracked-caps title, quiet count, italic serif
/// description, hairline rule.
private struct CollectionRow: View {
    let collection: SetupCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(collection.title.uppercased())
                        .scaledFont(size: 12, weight: .medium, relativeTo: .footnote)
                        .kerning(1.5)
                    Spacer()
                    if let count = collection.setupCount, count > 0 {
                        Kicker("\(count)", size: 10, color: .tertiary)
                            .monospacedDigit()
                    }
                }
                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .scaledFont(size: 13, design: .serif, relativeTo: .footnote)
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            Hairline(opacity: 0.12)
        }
        .contentShape(Rectangle())
    }
}
