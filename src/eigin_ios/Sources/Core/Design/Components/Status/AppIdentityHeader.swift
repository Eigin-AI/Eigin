import SwiftUI

/// The top of every connection screen, whichever kind of connection it is:
/// mark, name, kind, and status. Custom marks (like the Eigin brand avatar)
/// replace the standard `AppMark`.
struct AppIdentityHeader<Mark: View>: View {
    let name: String
    let kind: String?
    let state: ConnectionState
    let status: String

    @ViewBuilder private var mark: () -> Mark

    init(
        name: String,
        kind: String?,
        state: ConnectionState,
        status: String,
        @ViewBuilder mark: @escaping () -> Mark
    ) {
        self.name = name
        self.kind = kind
        self.state = state
        self.status = status
        self.mark = mark
    }

    var body: some View {
        VStack(spacing: Spacing.n16) {
            mark()
            VStack(spacing: Spacing.n4) {
                Text(name)
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)
                if let kind {
                    Text(kind)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
                AppStatusLine(state: state, label: status)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.n16)
        .padding(.bottom, Spacing.n8)
    }

    @Environment(\.colors) private var colors
}

extension AppIdentityHeader where Mark == AppMark {
    /// The standard header: an `AppMark` from a design icon or a letter.
    init(
        name: String,
        kind: String?,
        state: ConnectionState,
        status: String,
        icon: Image? = nil,
        letter: String? = nil,
        markSize: CGFloat = 64
    ) {
        self.init(name: name, kind: kind, state: state, status: status) {
            AppMark(icon: icon, letter: letter, size: markSize)
        }
    }
}
