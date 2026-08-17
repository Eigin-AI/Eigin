import SwiftUI

/// The bottom navigation bar that overlays the root content.
///
/// Sits at the bottom of the screen, extending into the safe area. The bar is
/// visible when the global `TabBarVisibility` depth is zero (no pushed views
/// have requested it hidden). Switching tabs resets the depth.
struct NavigationBarView: View {
    @Binding var selectedTab: RootTab
    @StateObject private var tabBarVisibility = TabBarVisibility.shared

    var body: some View {
        VStack {
            Spacer()
            if tabBarVisibility.isVisible {
                AppNavigationBar(background: .surface, tabs: [
                    AppNavigationTab(
                        icon: Iconography.Brand.avatar,
                        label: Localized.Ui.chats,
                        isSelected: selectedTab == .chats
                    ) {
                        selectedTab = .chats
                    },
                    AppNavigationTab(
                        icon: Iconography.Functional.avatar,
                        label: Localized.Ui.agent,
                        isSelected: selectedTab == .agent
                    ) {
                        selectedTab = .agent
                    },
                    AppNavigationTab(
                        icon: Iconography.Brand.settings,
                        label: Localized.Ui.settings,
                        isSelected: selectedTab == .settings
                    ) {
                        selectedTab = .settings
                    },
                ])
                .transition(.move(edge: .bottom))
            }
        }
        // Ignore the keyboard too so the bar stays anchored and never rides it.
        .ignoresSafeArea([.container, .keyboard], edges: .bottom)
    }
}

#Preview {
    NavigationBarView(selectedTab: .constant(.chats))
        .previewEnvironment()
}
