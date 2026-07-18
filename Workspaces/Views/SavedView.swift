import SwiftUI

/// The reader's clippings: saved setups in compact index rows, newest-saved
/// first, rendered entirely from disk so the section works offline.
struct SavedView: View {
    let store: SavedStore

    var body: some View {
        if store.saved.isEmpty {
            VStack(spacing: 12) {
                Kicker("Saved")
                Text("Nothing saved yet.")
                    .scaledFont(size: 15, design: .serif, relativeTo: .subheadline)
                    .italic()
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Kicker(
                        "\(store.saved.count) \(store.saved.count == 1 ? "setup" : "setups") — newest first",
                        size: 9,
                        color: .tertiary
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    ForEach(store.saved) { setup in
                        NavigationLink(value: setup) {
                            IndexResultRow(setup: setup)
                        }
                        .buttonStyle(.plain)

                        if setup.id != store.saved.last?.id {
                            Hairline(opacity: 0.12)
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}
