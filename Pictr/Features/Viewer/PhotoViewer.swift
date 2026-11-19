import AVKit
import Photos
import SwiftUI

/// Opens the full-screen viewer from anywhere: grids, pop-up previews, the deck.
@MainActor
@Observable
final class ViewerPresenter {
    struct Request: Identifiable {
        let id = UUID()
        var ids: [String]
        var index: Int
        /// Off in the deck, where the deck itself owns keep/delete.
        var showsActions: Bool
    }

    var request: Request?

    func open(_ ids: [String], at index: Int = 0, showsActions: Bool = true) {
        guard ids.indices.contains(index) else { return }
        request = Request(ids: ids, index: index, showsActions: showsActions)
    }
}

/// Photos-style viewer: swipe between items, pinch or double-tap to zoom, Live
/// Photos and videos play, details on demand, and keep / favorite / queue actions.
struct PhotoViewer: View {
    let request: ViewerPresenter.Request

    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var presenter
    @State private var index: Int
    @State private var items: [String: ReviewItem] = [:]
    @State private var sizes: [String: BucketMember] = [:]
    @State private var showsInfo = false
    @State private var chromeHidden = false
    @State private var loader = ImageLoader()
    @State private var notice: String?

    init(request: ViewerPresenter.Request) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var currentID: String { request.ids[index] }
    private var current: ReviewItem? { items[currentID] }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(request.ids.enumerated()), id: \.offset) { offset, id in
                ViewerPage(id: id, item: items[id], loader: loader, isCurrent: offset == index)
                    .tag(offset)
                    .onTapGesture { withAnimation(Theme.Motion.base) { chromeHidden.toggle() } }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { if !chromeHidden { topBar } }
        .overlay(alignment: .bottom) { if !chromeHidden { bottomBar } }
        .overlay(alignment: .center) {
            if let notice {
                Text(notice)
                    .font(Theme.Typeface.captionMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.x4).padding(.vertical, Theme.Space.x3)
                    .glassEffect()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(chromeHidden)
        .sensoryFeedback(.selection, trigger: index)
        .task { await loadMetadata() }
        .sheet(isPresented: $showsInfo) {
            ViewerInfo(item: current, member: sizes[currentID]) { showsInfo = false }
                .presentationDetents([.height(260)])
                .presentationBackground(.regularMaterial)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                showsInfo = false
                presenter.request = nil
            } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityLabel("Close")
            Spacer()
            VStack(spacing: 0) {
                if let date = current?.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).font(Theme.Typeface.headline)
                    Text(date.formatted(date: .omitted, time: .shortened)).font(Theme.Typeface.caption)
                }
            }
            .padding(.horizontal, Theme.Space.x4).padding(.vertical, Theme.Space.x2)
            .glassEffect()
            Spacer()
            Text("\(index + 1)/\(request.ids.count)")
                .font(Theme.Typeface.number)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, Theme.Space.x2)
                .glassEffect()
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.x4)
        .transition(.opacity)
    }

    private var bottomBar: some View {
        let id = currentID
        let decision = decisions.book.decision(for: id)
        let isFavorite = current?.isFavorite ?? false
        return GlassEffectContainer(spacing: Theme.Space.x3) {
            HStack(spacing: Theme.Space.x3) {
                barButton("Info", icon: "info.circle") { showsInfo = true }
                ShareLink(item: SharedPhoto(id: id, isVideo: current?.mediaKind == .video, client: library.client),
                          preview: SharePreview(current?.mediaKind == .video ? "Video" : "Photo",
                                                image: Image(systemName: current?.mediaKind == .video ? "video" : "photo"))) {
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly).font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel("Share")
                barButton(isFavorite ? "Unfavorite" : "Favorite", icon: isFavorite ? "heart.fill" : "heart") {
                    Task { await toggleFavorite() }
                }
                if request.showsActions {
                    barButton(decision == .keep ? "Kept" : "Keep", icon: decision == .keep ? "checkmark.circle.fill" : "checkmark.circle") {
                        decisions.markKept(id, creationDate: current?.creationDate)
                        show("Kept")
                    }
                    if decision == .trash {
                        barButton("Take back", icon: "arrow.uturn.backward") {
                            decisions.unqueue([id])
                            show("Removed from Ready to Delete")
                        }
                    } else {
                        Button {
                            guard !isFavorite else { show("Favorites are protected"); return }
                            decisions.queue(ids: [id])
                            show("Added to Ready to Delete")
                        } label: {
                            Label("Delete", systemImage: "trash.fill").labelStyle(.iconOnly)
                                .font(.title3).frame(width: 52, height: 52)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .tint(Theme.Palette.accent).foregroundStyle(.white)
                        .accessibilityLabel("Add to Ready to Delete")
                    }
                }
            }
            .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.bottom, Theme.Space.x4)
        .transition(.opacity)
        .sensoryFeedback(.impact(weight: .light), trigger: decision)
    }

    private func barButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.iconOnly).font(.title3).frame(width: 52, height: 52)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityLabel(title)
    }

    private func toggleFavorite() async {
        guard var item = current else { return }
        let newValue = !item.isFavorite
        do {
            try await library.setFavorite(newValue, id: item.id)
            item.isFavorite = newValue
            items[item.id] = item
            // A favorite is protected, so it can't stay queued.
            if newValue, decisions.book.decision(for: item.id) == .trash { decisions.unqueue([item.id]) }
            show(newValue ? "Added to Favorites" : "Removed from Favorites")
        } catch {
            show("Couldn't change Favorites")
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { notice = nil }
        }
    }

    private func loadMetadata() async {
        let client = library.client
        let ids = request.ids
        let (loaded, members) = await Task.detached(priority: .userInitiated) {
            (client.reviewItems(ids: ids), client.members(for: ids))
        }.value
        items = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sizes = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

private struct ViewerPage: View {
    let id: String
    let item: ReviewItem?
    let loader: ImageLoader
    let isCurrent: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if item?.mediaKind == .video, let player {
                    VideoPlayer(player: player)
                } else if let livePhoto {
                    LivePhotoView(photo: livePhoto).aspectRatio(contentMode: .fit)
                } else if let image {
                    ZoomableImage(image: image)
                } else {
                    ProgressView().tint(Theme.Palette.textPrimary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: id) {
                let pixels = CGSize(width: geo.size.width * displayScale * 2, height: geo.size.height * displayScale * 2)
                for await next in loader.images(for: id, targetSize: pixels) { image = next }
            }
            .task(id: "\(id)-\(item?.mediaKind == .video)-\(item?.isLivePhoto == true)") {
                guard let item else { return }
                if item.mediaKind == .video, let playerItem = await loader.playerItem(for: id) {
                    player = AVPlayer(playerItem: playerItem)
                } else if item.isLivePhoto {
                    let size = CGSize(width: geo.size.width * displayScale, height: geo.size.height * displayScale)
                    livePhoto = await loader.livePhoto(for: id, targetSize: size)
                }
            }
            .onChange(of: isCurrent) { _, current in if !current { player?.pause() } }
        }
        .ignoresSafeArea()
    }
}

/// Pinch and double-tap zoom backed by UIScrollView, so it cooperates with paging.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .clear
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        ])
        context.coordinator.imageView = view
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private struct ViewerInfo: View {
    let item: ReviewItem?
    let member: BucketMember?
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x3) {
            HStack {
                Eyebrow("Details")
                Spacer()
                Button("Done", action: done)
                    .font(Theme.Typeface.bodyMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            if let date = item?.creationDate {
                row("Taken", date.formatted(date: .complete, time: .shortened))
            }
            if let item {
                row(item.mediaKind == .video ? "Video" : item.isLivePhoto ? "Live Photo" : "Photo",
                    "\(item.pixelWidth) × \(item.pixelHeight)"
                        + (item.mediaKind == .video ? ", " + Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)) : ""))
            }
            if let member {
                row("Size", ByteFormat.string(member.size.bytes) + (member.size.isEstimated ? " (estimated)" : ""))
                row("Stored", storedText(member.availability))
            }
            Spacer()
        }
        .padding(Theme.Space.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storedText(_ availability: Availability) -> String {
        switch availability {
        case .onDevice: "On this iPhone"
        case .cloudOnly: "iCloud only, not on this iPhone"
        case .unknown: "Unknown"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.Typeface.callout).foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value).font(Theme.Typeface.bodyMedium).foregroundStyle(Theme.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Long-press pop-up for any thumbnail: a large preview plus the common actions.
    func photoContextMenu(id: String, in ids: [String], presenter: ViewerPresenter,
                          decisions: DecisionsModel, provider: ThumbnailProvider,
                          isFavorite: Bool = false) -> some View {
        contextMenu {
            Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
                // Presenting while the menu is still animating away is dropped; wait it out.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    presenter.open(ids, at: ids.firstIndex(of: id) ?? 0)
                }
            }
            Button("Keep", systemImage: "checkmark.circle") { decisions.markKept(id) }
            if decisions.book.decision(for: id) == .trash {
                Button("Remove from Ready to Delete", systemImage: "arrow.uturn.backward") { decisions.unqueue([id]) }
            } else if !isFavorite {
                Button("Add to Ready to Delete", systemImage: "trash", role: .destructive) { decisions.queue(ids: [id]) }
            }
        } preview: {
            Thumb(id: id, provider: provider, pixels: 900)
                .frame(width: 320, height: 420)
        }
    }
}
