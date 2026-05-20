import SwiftUI

/// Header menu for filtering the chat list by space and accessing space management.
///
/// The trigger label is sized to match a medium `AppActionButton` so it sits
/// comfortably in the leading slot of `AppNavigationHeader`. When no space is
/// selected, a generic filter icon shows. When a space is active, its emoji
/// stands in as the indicator.
struct SpaceFilterMenu: View {
    let spaces: [Space]
    @Binding var selectedSpaceID: UUID?
    let onManageSpaces: () -> Void

    @Environment(\.colors) private var colors

    private var selectedSpace: Space? {
        guard let id = selectedSpaceID else { return nil }
        return spaces.first { $0.id == id }
    }

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
            triggerLabel
        }
    }

    private var triggerLabel: some View {
        Group {
            if let space = selectedSpace {
                Text(space.emoji)
                    .font(.system(size: 28))
            } else {
                Image(systemName: "line.3.horizontal.decrease")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(colors.icon.standard.base)
                    .frame(width: Sizing.Button.Icon.medium, height: Sizing.Button.Icon.medium)
            }
        }
        .frame(width: Sizing.Button.Action.medium, height: Sizing.Button.Action.medium)
        .contentShape(Circle())
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
