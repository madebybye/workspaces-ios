import SwiftUI

/// Setups in a curated collection, pushed from the INDEX. Membership is by
/// direct reference (setups hold a `collections` reference array), queried
/// through the shared paginated `FeedStore`.
struct CollectionResultsView: View {
    let collection: SetupCollection
    @State private var store: FeedStore

    init(collection: SetupCollection) {
        self.collection = collection
        let store = FeedStore()
        store.collectionId = collection.id
        _store = State(initialValue: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Collection", size: 10, color: .tertiary)
                Text(collection.title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .lineSpacing(2)
                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                Hairline()
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            SetupResultsList(store: store, emptyText: "Nothing in this collection yet.")
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Kicker("Collection", size: 11, color: .primary)
            }
        }
        .task { await store.loadInitial() }
    }
}
