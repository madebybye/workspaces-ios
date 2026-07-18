import SwiftUI

/// Setups featuring a given piece of gear, pushed from a detail's GEAR
/// section or from the INDEX gear list. Reuses the paginated `FeedStore`
/// with a GROQ token `match` on gear names, so "Herman Miller Aeron" also
/// finds "Herman Miller Aeron Chair".
struct GearResultsView: View {
    let gear: GearRef
    @State private var store: FeedStore

    init(gear: GearRef) {
        self.gear = gear
        let store = FeedStore()
        store.gearName = gear.name
        _store = State(initialValue: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Featuring", size: 10, color: .tertiary)
                Text(gear.name)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .lineSpacing(2)
                Hairline()
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            SetupResultsList(store: store, emptyText: "No other setups feature this yet.")
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Kicker("Gear", size: 11, color: .primary)
            }
        }
        .task { await store.loadInitial() }
    }
}
