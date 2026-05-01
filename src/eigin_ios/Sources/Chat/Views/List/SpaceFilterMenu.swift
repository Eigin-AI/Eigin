import SwiftUI

/// Toolbar menu for filtering the chat list by space and accessing space management.
struct SpaceFilterMenu: View {
    let spaces: [Space]
    @Binding var selectedSpaceID: UUID?
    let onManageSpaces: () -> Void

    var body: some View {
        Menu {
            Button {
                selectedSpaceID = nil
            } label: {
                if selectedSpaceID == nil {
                    Label(Localized.Space.Filter.allChats, systemImage: "checkmark")
                } else {
                    Text(Localized.Space.Filter.allChats)
                }
            }

            if !spaces.isEmpty {
                Divider()

                ForEach(spaces) { space in
                    Button {
                        selectedSpaceID = space.id
                    } label: {
                        if selectedSpaceID == space.id {
                            Label {
                                spaceLabel(space)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            spaceLabel(space)
                        }
                    }
                }
            }

            Divider()

            Button {
                onManageSpaces()
            } label: {
                Label(Localized.Space.Filter.manageSpaces, systemImage: "square.grid.2x2")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
    }

    private func spaceLabel(_ space: Space) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(space.emoji) \(space.name)")
            if space.isPrivate {
                Image(systemName: "eye.slash")
                    .font(.caption2)
            }
        }
    }
}
