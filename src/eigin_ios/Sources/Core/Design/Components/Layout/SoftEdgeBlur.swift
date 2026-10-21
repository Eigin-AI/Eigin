import SwiftUI
import UIKit

/// The soft edge's blur: the system backdrop blur over the content, masked to
/// ``SoftEdgeCurve/blurStops(full:end:)``.
///
/// Uses only public API. The system blur has a fixed strength, so the mask
/// alone sets how much of it shows.
struct SoftEdgeBlur: UIViewRepresentable {
    let edge: VerticalEdge
    /// Where the blur is full to, and where it ends, as shares of the height.
    let full: Double
    let end: Double
    /// How much of the blur shows, from 0 to 1. Set every frame of a fade.
    let visibility: Double

    func makeUIView(context _: Context) -> MaskedBlurView {
        MaskedBlurView(mask: GradientMaskView(fromTop: edge == .top))
    }

    func updateUIView(_ view: MaskedBlurView, context _: Context) {
        guard let mask = view.mask as? GradientMaskView else { return }
        // The mask fades, not the blur: an effect view can't be faded.
        UIView.performWithoutAnimation {
            mask.stops = SoftEdgeCurve.blurStops(full: full, end: end)
            mask.alpha = visibility
        }
    }
}

/// The system blur, cut to a mask that follows its size.
final class MaskedBlurView: UIVisualEffectView {
    init(mask: UIView) {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        isUserInteractionEnabled = false
        self.mask = mask
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Outside any running animation, or the mask grows in from a corner.
        UIView.performWithoutAnimation {
            mask?.frame = bounds
        }
    }
}

/// A vertical alpha gradient, for masking a blur.
final class GradientMaskView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradient: CAGradientLayer {
        layer as! CAGradientLayer
    }

    var stops: [(location: Double, coverage: Double)] = [] {
        didSet {
            gradient.colors = stops.map { UIColor.black.withAlphaComponent($0.coverage).cgColor }
            gradient.locations = stops.map { NSNumber(value: $0.location) }
        }
    }

    init(fromTop: Bool) {
        super.init(frame: .zero)
        gradient.startPoint = CGPoint(x: 0.5, y: fromTop ? 0 : 1)
        gradient.endPoint = CGPoint(x: 0.5, y: fromTop ? 1 : 0)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
