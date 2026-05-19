import UIKit

/// Restores the interactive edge-swipe pop gesture when the navigation bar
/// is hidden via `.toolbar(.hidden, for: .navigationBar)`.
///
/// By default, SwiftUI disables the gesture as soon as the toolbar is hidden.
/// This extension sets the gesture delegate back to the navigation controller
/// itself so the gesture continues to work normally.
///
/// `gestureRecognizerShouldBegin` is gated on `viewControllers.count > 1`
/// so the gesture is only active when there is a previous screen to pop to.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
