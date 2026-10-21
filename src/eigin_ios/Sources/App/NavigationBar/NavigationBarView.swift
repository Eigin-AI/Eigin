import Factory
import SwiftUI

/// The bottom navigation bar that overlays the root content.
///
/// Sits at the bottom of the screen, extending into the safe area. `ContentView`
/// hides it while any `.hidesTabBar()` view is on-screen (see
/// `HidesTabBarPreferenceKey`).
struct NavigationBarView: View {
    @Binding var selectedTab: RootTab
    @Injected(\.tabBarVisibility) private var tabBarVisibility

    var body: some View {
        VStack {
            Spacer()
            if tabBarVisibility.isVisible {
                AppNavigationBar(tabs: [
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
                .transition(.opacity)
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
