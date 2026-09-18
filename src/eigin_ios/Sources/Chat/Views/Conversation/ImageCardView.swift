import Factory
import SwiftUI

/// An image card's load life, mirrored from the web design's `ImageState`.
enum ImageLoadState: Equatable {
    /// Withheld: a remote image no one has consented to fetch yet.
    case blocked
    case loading
    /// The decoded image's natural pixel size; the card derives its ratio.
    case loaded(CGSize)
    case failed
}

/// A link awaiting the user's leave-Eigin check, presented as a sheet.
private struct PendingLink: Identifiable {
    let id = UUID()
    let href: String
}

/// A standalone image in a conversation, as a card.
///
/// Height is fixed (from the design tokens) for every image and every state, so
/// the feed never moves: the shape an image turns out to be changes its width,
/// never the space it sits in. It aspect-fills that box — scaled to cover and
/// cropped, never letterboxed or stretched.
///
/// Remote images start withheld: fetching one discloses the user's IP to a host
/// the model chose, so no request is made until the card is tapped. Every other
/// source (data URI, file) loads directly.
struct ImageCardView: View {
    let src: String
    var alt: String?
    var href: String?

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Injected(\.imageCache) var cache: ImageCache

    @State private var state: ImageLoadState
    @State private var image: UIImage?
    /// The plate's fitted width — `min(column, cardWidth)` — measured, since
    /// the ratio cap alone doesn't know how narrow the column is.
    @State private var plateWidth: CGFloat = 0
    @State private var previewURL: URL?
    @State private var pendingLink: PendingLink?
    /// The card grows in once, on its first arrival; a card restored from the
    /// in-memory cache skips it, so a list recycle never replays the reveal.
    @State private var appeared: Bool

    init(src: String, alt: String? = nil, href: String? = nil) {
        self.src = src
        self.alt = alt
        self.href = href

        let memory = Container.shared.imageCache()
        if ImageSource.isRemote(src), let decoded = memory.cachedImage(src) {
            // Already consented to this session: start loaded, before the first
            // frame, so a recycled view never re-enters the withheld square.
            _image = State(initialValue: decoded)
            _state = State(initialValue: .loaded(decoded.size))
            _appeared = State(initialValue: true)
        } else if ImageSource.isRemote(src), memory.isKnownFailed(src) {
            // Failed this session: stay failed across recycles, not withheld.
            _state = State(initialValue: .failed)
            _appeared = State(initialValue: true)
        } else {
            _state = State(initialValue: ImageSource.isRemote(src) ? .blocked : .loading)
            _appeared = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n12) {
            plate
            if let alt, !alt.isEmpty {
                Text(alt)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .leading)
        .onAppear(perform: growIn)
        .task(id: src) { await checkCache() }
        .sheet(item: $pendingLink) { link in
            ExternalLinkSheet(href: link.href)
        }
        .fullScreenCover(isPresented: viewerBinding) {
            if let previewURL {
                AttachmentPreview(url: previewURL, title: alt, isPresented: viewerBinding)
                    .ignoresSafeArea()
            }
        }
    }

    /// The reveal: fade and settle from a hair small, out of the leading edge.
    /// Reduced motion just arrives.
    private func growIn() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(Animations.gentle) {
                appeared = true
            }
        }
    }

    // MARK: - Plate

    private var plate: some View {
        ZStack(alignment: .topTrailing) {
            imageLayer
            cover
                .opacity(isLoaded ? 0 : 1)
                .accessibilityHidden(isLoaded)
            badge
                .opacity(isLoaded ? 1 : 0)
        }
        .frame(maxWidth: cardWidth, alignment: .leading)
        .frame(height: Sizing.Image.height)
        .background { colors.surface.standard.elevated }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { plateWidth = $0 }
        .overlay { tapLayer }
    }

    /// The image scales to cover the plate and is cropped to it — top, sides
    /// and bottom — so no state ever shows surface around the picture.
    @ViewBuilder
    private var imageLayer: some View {
        if let image, isLoaded {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .transition(.opacity)
        }
    }

    /// The plate is a button wherever there's an action: tap a withheld card to
    /// load it, a loaded one to follow its link or open the viewer. Failed keeps
    /// its place inert.
    @ViewBuilder
    private var tapLayer: some View {
        if action != nil {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onTapGesture { action?() }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    /// Cover for the three states that aren't the picture: the ring for
    /// waiting, the globe for withheld, the warning for broken. Kept mounted
    /// (just faded) so the image crossfades over it instead of replacing it.
    private var cover: some View {
        VStack(spacing: Spacing.n8) {
            switch state {
            case .failed:
                glyph(Iconography.Functional.warning, size: Sizing.Image.Icon.cover)
                    .foregroundStyle(colors.icon.signal.notice)
                Text(Localized.ImageCard.failedHeadline)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.base)
                if !host.isEmpty {
                    Text(host)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            case .blocked:
                glyph(Iconography.Functional.globe, size: Sizing.Image.Icon.cover)
                    .foregroundStyle(colors.icon.standard.muted)
                Text(coverHeadline)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.base)
                Text(Localized.ImageCard.tapToLoad)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            case .loading:
                SweepRing(size: Sizing.Image.Icon.ring)
            case .loaded:
                EmptyView()
            }
        }
        .padding(Spacing.n16)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func glyph(_ icon: Image, size: CGFloat) -> some View {
        icon
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    /// Globe and host: says the image leads somewhere. Hidden until loaded.
    /// Narrower than 220pt and the host is a stub worth nothing — the globe
    /// alone says it, as the web card's container query does. The check reads
    /// the plate's real width, so a column-capped wide image answers honestly.
    @ViewBuilder
    private var badge: some View {
        if href != nil, isLoaded, !host.isEmpty, plateWidth >= Sizing.Image.badgeHostMinWidth {
            HStack(spacing: Spacing.n4) {
                glyph(Iconography.Functional.globe, size: Sizing.Image.Icon.badge)
                Text(host)
                    .typography(Typography.miniLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
            }
            .padding(.init(
                top: Spacing.n4,
                leading: Spacing.n8,
                bottom: Spacing.n4,
                trailing: Spacing.n8
            ))
            .background(colors.surface.standard.base.opacity(0.88), in: Capsule())
            .foregroundStyle(colors.text.standard.base)
            .padding(Spacing.n8)
        }
    }

    // MARK: - Sizing

    private var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// The card's shape: the image's true ratio clamped to the design's bounds,
    /// or the square placeholder before it arrives.
    private var ratio: CGFloat {
        switch state {
        case .loaded(let size) where size.height > 0:
            min(max(size.width / size.height, Sizing.Image.Ratio.min), Sizing.Image.Ratio.max)
        default:
            Sizing.Image.Ratio.placeholder
        }
    }

    private var cardWidth: CGFloat {
        Sizing.Image.height * ratio
    }

    // MARK: - Tap action

    private var action: (() -> Void)? {
        if case .failed = state { return nil }
        // A load already under way: no second consent, no dead viewer tap.
        if case .loading = state { return nil }
        if case .blocked = state { return load }
        guard let href else { return openViewer }
        // The model chose the link, not you: leaving is a second, deliberate tap.
        return { pendingLink = .init(href: href) }
    }

    /// Withheld → fetching. The request is the thing being withheld: one tap
    /// consents to it, and the result is cached on disk for every next view.
    private func load() {
        guard case .blocked = state else { return }
        state = .loading
        Task { await loadNow() }
    }

    private func loadNow() async {
        let data = await cache.fetch(src)
        guard !Task.isCancelled else { return }
        if let decoded = data.flatMap({ decode($0, for: src) }) {
            setLoaded(decoded)
        } else {
            cache.rememberFailure(src)
            state = .failed
        }
    }

    private func openViewer() {
        guard previewURL == nil else { return }
        Task {
            previewURL = await cache.previewFile(for: src)
        }
    }

    private var viewerBinding: Binding<Bool> {
        Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )
    }

    // MARK: - State

    /// On appear: bytes already on disk (an earlier consent) show loaded with no
    /// network; an uncached remote image stays withheld; anything else loads.
    /// On appear, for a card still withheld: bytes already on disk (an earlier
    /// consent) show loaded with no network; a download started by an earlier
    /// recycled view is ridden, not restarted; otherwise the image stays
    /// withheld until tapped. A never-consented local image just loads.
    private func checkCache() async {
        switch state {
        case .blocked, .loading:
            break
        case .loaded, .failed:
            // Settled already (restored from memory, failed before): don't move.
            return
        }

        if let decoded = await cache.data(for: src)
            .flatMap({ decode($0, for: src) })
        {
            setLoaded(decoded)
            return
        }

        guard ImageSource.isRemote(src) else {
            await loadNow()
            return
        }

        // A fetch a previous view of this card consented to may still be
        // running: wait on it rather than flipping back to withheld.
        guard await cache.isFetching(src) else { return }
        await loadNow()
    }

    /// The image and the width settle as one gesture, out of the square that
    /// promised nothing; reduced motion skips the spring and just arrives.
    private func setLoaded(_ decoded: UIImage) {
        image = decoded
        let size = decoded.size
        if reduceMotion {
            state = .loaded(size)
        } else {
            withAnimation(Animations.gentle) {
                state = .loaded(size)
            }
        }
    }

    /// Decodes cached bytes and files the picture into the session memory pool.
    private func decode(_ data: Data, for src: String) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        cache.remember(image, for: src)
        return image
    }

    // MARK: - Host and labels

    /// Host of the link when there is one, else of the image itself. Empty where
    /// there is no host to name, as a data URI has none.
    private var host: String {
        ImageSource.host(of: href ?? src)
    }

    private var coverHeadline: String {
        if host.isEmpty {
            return Localized.ImageCard.fromAnotherSite
        }
        return Localized.ImageCard.fromHost(host)
    }

    private var accessibilityLabel: String {
        switch state {
        case .blocked:
            return host.isEmpty
                ? Localized.ImageCard.a11yShowImage
                : Localized.ImageCard.a11yShowImageFrom(host)
        case .loaded:
            if href != nil {
                return Localized.ImageCard.a11yOpenHost(host.isEmpty ? (href ?? "") : host)
            }
            if let alt, !alt.isEmpty {
                return Localized.ImageCard.a11yViewImage(alt)
            }
            return Localized.ImageCard.viewImage
        case .loading:
            return Localized.ImageCard.loading
        case .failed:
            return coverHeadline
        }
    }
}

// MARK: - External link check

/// The check before a link leaves Eigin. The model chose the link, not the
/// user, so the host is named plainly and opening is a second, deliberate tap.
/// Mirrors `ExternalLinkSheet.svelte`.
private struct ExternalLinkSheet: View {
    let href: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var destination: String {
        let host = ImageSource.host(of: href)
        return host.isEmpty ? href : host
    }

    var body: some View {
        AppFittedSheet(
            header: {
                AppSheetHeader(
                    title: Localized.ImageCard.leaveTitle,
                    description: Localized.ImageCard.leaveDescription(destination)
                )
            },
            primary: {
                VStack(spacing: Spacing.n8) {
                    AppButton(Localized.ImageCard.openLink) {
                        dismiss()
                        if let url = URL.fromMixedEncodingString(href) {
                            openURL(url)
                        }
                    }
                    AppButton(Localized.ImageCard.stayHere, variant: .secondary) {
                        dismiss()
                    }
                }
                .padding(.horizontal, Spacing.n16)
            }
        )
    }
}

// MARK: - Source helpers

/// Parsing helpers for markdown image sources: what counts as remote (and so
/// withheld), and the host to name alongside it.
enum ImageSource {
    /// Fetching a `http(s)` source discloses the user's IP to the host, so those
    /// withhold by default. Data URIs and files are already local.
    static func isRemote(_ src: String) -> Bool {
        URL.fromMixedEncodingString(src)?.isRemoteHTTP ?? false
    }

    /// Root domain of the link when there is one, else of the image itself —
    /// `images.unsplash.com` names itself `unsplash.com`. Empty where there is
    /// no host to name, as a data URI has none.
    static func host(of src: String) -> String {
        URL.fromMixedEncodingString(src)?.rootDisplayDomain() ?? ""
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.n24) {
        ImageCardView(src: "https://example.com/photo.jpg", alt: "A wide photo")
        ImageCardView(
            src: "https://example.com/photo.jpg",
            alt: "Linked image",
            href: "https://example.com"
        )
    }
    .padding()
    .resolveTheme()
}
