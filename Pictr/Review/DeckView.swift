import AVFoundation
import Photos
import SwiftUI

enum DeckMode: Equatable {
    /// Real decisions: left queues into Ready to Delete.
    case decide
    /// Taste training: answers teach the model and queue nothing.
    case train
}

/// Swipe deck: right keeps, left queues for deletion (or, in training, marks
/// "would delete"), undo walks back. When the top card starts a burst, Compare
/// opens the whole moment side by side to keep the best.
struct DeckView: View {
    let title: String
    let items: [ReviewItem]
    var today: Date = .now
    var mode: DeckMode = .decide

    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    @State private var session: ReviewSession
    /// One entry per session action; a compare restores its whole moment.
    @State private var undoRecords: [[DecisionBook.Record?]] = []
    @State private var undoTaste: [[Decision?]] = []
    @State private var comparing: MomentRequest?
    @State private var drag: CGSize = .zero
    @State private var notice: String?
    @State private var loader = ImageLoader()
    @State private var thumbnails = ThumbnailProvider()
    @State private var isMuted = true
    @State private var decisionTick = 0
    @State private var lastDecision: Decision = .keep
    @State private var protectTick = 0

    /// -1 past the delete threshold, 1 past keep, 0 between. Drives a selection tick.
    private var thresholdZone: Int {
        drag.width > Self.swipeThreshold ? 1 : drag.width < -Self.swipeThreshold ? -1 : 0
    }

    private static let swipeThreshold: CGFloat = 110

    struct MomentRequest: Identifiable {
        var items: [ReviewItem]
        var id: String { items.first?.id ?? "" }
    }

    /// The burst the top card starts, among what's left in this deck.
    private var moment: [ReviewItem] {
        Array(session.items[Moment.run(in: session.items, from: session.index)])
    }
    @Environment(\.dismiss) private var dismiss

    init(title: String, items: [ReviewItem], today: Date = .now, mode: DeckMode = .decide) {
        self.title = title
        self.items = items
        self.today = today
        self.mode = mode
        _session = State(initialValue: ReviewSession(items: items))
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: Theme.Space.x4) {
                if let item = session.current {
                    progress
                    card(for: item)
                    controls
                } else {
                    finished
                }
            }
            .padding(.horizontal, Theme.Space.x5)
            .padding(.bottom, Theme.Space.x4)
        }
        .navigationTitle(title)
        .settingsToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .top) {
            if let notice {
                Label(notice, systemImage: "heart.fill")
                    .font(Theme.Typeface.captionMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.x4).padding(.vertical, Theme.Space.x3)
                    .glassEffect()
                    .padding(.top, Theme.Space.x2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: session.index, initial: true) { preheat() }
        .sensoryFeedback(.selection, trigger: thresholdZone) { _, new in new != 0 }
        .sensoryFeedback(trigger: decisionTick) { _, _ in
            lastDecision == .trash ? .impact(weight: .medium) : .impact(flexibility: .soft)
        }
        .sensoryFeedback(.warning, trigger: protectTick)
        .fullScreenCover(item: $comparing) { request in
            PickBestView(items: request.items, mode: mode) { decideMoment(request.items, $0) }
        }
    }

    private var targetSize: CGSize {
        CGSize(width: 420 * displayScale, height: 620 * displayScale)
    }

    /// The current photo, blurred, behind everything, so the glass picks up its colour.
    private var backdrop: some View {
        ZStack {
            Theme.Palette.bgDeep
            if let id = session.current?.id {
                Thumb(id: id, provider: thumbnails, pixels: 200)
                    .blur(radius: 60)
                    .opacity(0.55)
                    .id(id)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.clear, Theme.Palette.bgDeep.opacity(0.8)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(Theme.Motion.slow, value: session.current?.id)
    }

    private var progress: some View {
        HStack(spacing: Theme.Space.x4) {
            Text("\(min(session.index + 1, session.items.count)) of \(session.items.count)")
                .font(Theme.Typeface.number)
            Divider().frame(height: 14)
            Label("\(session.keptCount)", systemImage: "checkmark")
                .font(Theme.Typeface.number)
            Label("\(session.trashedCount)", systemImage: "trash.fill")
                .font(Theme.Typeface.number)
                .labelStyle(TintedIconLabelStyle(tint: Theme.Palette.accent))
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.x4).padding(.vertical, Theme.Space.x2)
        .glassEffect()
        .accessibilityElement(children: .combine)
    }

    private func card(for item: ReviewItem) -> some View {
        PhotoCard(item: item, today: today, loader: loader, targetSize: targetSize, drag: drag, isMuted: $isMuted,
                  deleteLabel: mode == .train ? "Would delete" : "Delete")
            .overlay(alignment: .topTrailing) { compareButton }
            .id(item.id)
            .onTapGesture {
                if item.mediaKind == .video { isMuted.toggle() } else { viewer.open([item.id], showsActions: false) }
            }
            .offset(x: drag.width, y: drag.height * 0.2)
            .rotationEffect(.degrees(Double(drag.width / 22)))
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let x = value.predictedEndTranslation.width
                        if x > Self.swipeThreshold { decide(.keep) }
                        else if x < -Self.swipeThreshold { decide(.trash) }
                        else { withAnimation(.spring) { drag = .zero } }
                    }
            )
            .accessibilityAction(named: "Keep") { decide(.keep) }
            .accessibilityAction(named: "Delete") { decide(.trash) }
            .accessibilityAction(named: "Open full screen") { viewer.open([item.id], showsActions: false) }
            .accessibilityActions {
                if moment.count > 1 {
                    Button("Compare \(moment.count) shots from this moment") { comparing = MomentRequest(items: moment) }
                }
            }
    }

    @ViewBuilder private var compareButton: some View {
        let shots = moment
        if shots.count > 1 {
            Button { comparing = MomentRequest(items: shots) } label: {
                Label("Compare \(shots.count)", systemImage: "rectangle.split.1x2")
                    .font(Theme.Typeface.captionMedium)
            }
            .buttonStyle(.glass)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(Theme.Space.x4)
            .opacity(drag == .zero ? 1 : 0)
            .allowsHitTesting(drag == .zero)
            .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: Theme.Space.x6) {
            HStack(spacing: Theme.Space.x6) {
                Button { decide(.trash) } label: {
                    Image(systemName: "trash.fill").font(.title2).frame(width: 64, height: 64)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.Palette.accent)
                .foregroundStyle(.white)
                .accessibilityLabel("Delete")

                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.headline).frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .disabled(!session.canUndo)
                .accessibilityLabel("Undo")

                Button { decide(.keep) } label: {
                    Image(systemName: "checkmark").font(.title2.weight(.semibold)).frame(width: 64, height: 64)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .accessibilityLabel("Keep")
            }
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x5) {
            Spacer()
            PictrMark(size: 88)
            Text(mode == .train ? "Learned from \(session.history.count) answers" : "Deck done")
                .font(Theme.Typeface.hero)
                .kerning(-1)
                .foregroundStyle(Theme.Palette.textPrimary)
            if mode == .decide {
                HStack(spacing: Theme.Space.x3) {
                    FinishStat(value: session.keptCount, label: "Kept", systemImage: "checkmark")
                    FinishStat(value: session.trashedCount, label: "Ready to Delete", systemImage: "trash.fill", red: true)
                }
            }
            Text(mode == .train ? "Nothing was queued. Tap Update in Cleanup to refresh Maybe Delete with what Pictr learned."
                                : "Nothing is deleted until you confirm in Ready to Delete.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            VStack(spacing: Theme.Space.x2) {
                Button { dismiss() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                if session.canUndo {
                    Button { undo() } label: {
                        Text("Undo last").frame(maxWidth: .infinity)
                    }
                    .secondaryGlassButton()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decide(_ decision: Decision) {
        guard let item = session.current else { return }
        if decision == .trash && item.isFavorite {
            protectTick += 1
            show("Favorites are protected")
            withAnimation(.spring) { drag = .zero }
            return
        }
        switch mode {
        case .decide:
            let previous = decisions.book.entry(for: item.id)
            decisions.record(decision, for: item)
            undoRecords.append([previous])
        case .train:
            undoTaste.append([decisions.book.taste[item.id]])
            decisions.recordTaste(decision, for: item.id)
        }
        lastDecision = decision
        decisionTick += 1
        let exit = CGSize(width: decision == .keep ? 600 : -600, height: drag.height)
        withAnimation(.easeOut(duration: 0.2)) { drag = exit }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            session.decide(decision)
            drag = .zero
        }
    }

    /// A compare's verdict: one decision per shot, applied and undone as one action.
    private func decideMoment(_ items: [ReviewItem], _ verdict: [Decision]) {
        // The deck can't have moved while the cover was up, but don't trust that blindly.
        guard verdict.count == items.count, Array(session.items.dropFirst(session.index).prefix(items.count)) == items
        else { return }
        switch mode {
        case .decide:
            undoRecords.append(items.map { decisions.book.entry(for: $0.id) })
            decisions.record(Array(zip(verdict, items)))
        case .train:
            undoTaste.append(items.map { decisions.book.taste[$0.id] })
            for (decision, item) in zip(verdict, items) { decisions.recordTaste(decision, for: item.id) }
        }
        session.decide(batch: verdict)
        lastDecision = verdict.contains(.trash) ? .trash : .keep
        decisionTick += 1
        drag = .zero
    }

    private func undo() {
        let steps = session.undo()
        guard !steps.isEmpty else { return }
        switch mode {
        case .decide:
            guard let previous = undoRecords.popLast() else { return }
            for (step, record) in zip(steps, previous) { decisions.restore(step.item.id, to: record) }
        case .train:
            guard let previous = undoTaste.popLast() else { return }
            for (step, decision) in zip(steps, previous) { decisions.restoreTaste(step.item.id, to: decision) }
        }
        drag = .zero
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { notice = nil }
        }
    }

    private func preheat() {
        loader.preheat(session.upcoming.map(\.id), targetSize: targetSize)
    }
}

struct PhotoCard: View {
    let item: ReviewItem
    let today: Date
    let loader: ImageLoader
    let targetSize: CGSize
    let drag: CGSize
    @Binding var isMuted: Bool
    var deleteLabel = "Delete"

    @State private var image: UIImage?
    @State private var playerItem: AVPlayerItem?
    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
            .fill(Theme.Palette.surface)
            .overlay {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                        // Fill overflows the frame; only the visible frame takes touches.
                        .allowsHitTesting(false)
                    } else {
                        ProgressView()
                    }
                    if let playerItem {
                        LoopingVideoView(item: playerItem, isMuted: isMuted)
                            .transition(.opacity)
                    } else if let livePhoto {
                        LivePhotoView(photo: livePhoto)
                    }
                }
            }
            .overlay(alignment: .topLeading) { mediaBadge }
            .overlay { swipeTint }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(edgeColor, lineWidth: drag.width < -30 ? 2 : 1))
            .shadow(color: glowColor, radius: 28, y: 8)
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .top) { stamp }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .task(id: item.id) {
                for await next in loader.images(for: item.id, targetSize: targetSize) {
                    image = next
                }
            }
            .task(id: item.id) {
                if item.mediaKind == .video {
                    let item = await loader.playerItem(for: item.id)
                    withAnimation(Theme.Motion.slow) { playerItem = item }
                } else if item.isLivePhoto {
                    livePhoto = await loader.livePhoto(for: item.id, targetSize: targetSize)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let years = OnThisDay.yearsAgo(item.creationDate, from: today), years > 0 {
                Text(years == 1 ? "1 year ago" : "\(years) years ago").font(Theme.Typeface.headline)
            }
            HStack(spacing: Theme.Space.x2) {
                if let date = item.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
                if item.isFavorite { Image(systemName: "heart.fill").accessibilityLabel("Favorite") }
                if item.mediaKind == .video {
                    Label(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond)), systemImage: "video.fill")
                }
            }
            .font(Theme.Typeface.caption)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, Theme.Space.x4).padding(.vertical, Theme.Space.x3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(Theme.Space.x4)
    }

    @ViewBuilder private var mediaBadge: some View {
        if item.mediaKind == .video {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .circle)
                .padding(Theme.Space.x4)
                .accessibilityLabel(isMuted ? "Muted. Tap the video to unmute." : "Sound on")
        } else if item.isLivePhoto {
            Label("Live", systemImage: "livephoto")
                .font(Theme.Typeface.captionMedium)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x1 + 2)
                .glassEffect()
                .padding(Theme.Space.x4)
                .accessibilityLabel("Live Photo. Press and hold to play.")
        }
    }

    /// How far the drag has committed toward a side, 0...1.
    private var leftPull: Double { Double(min(max(-drag.width / 160, 0), 1)) }
    private var rightPull: Double { Double(min(max(drag.width / 160, 0), 1)) }

    /// Delete floods the photo red from the left edge; keep lifts it with light.
    private var swipeTint: some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.accent.opacity(0.75), Theme.Palette.accent.opacity(0.15)],
                           startPoint: .leading, endPoint: .trailing)
                .opacity(leftPull * 0.8)
            LinearGradient(colors: [.clear, .white.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                .opacity(rightPull)
        }
        .allowsHitTesting(false)
    }

    private var edgeColor: Color {
        leftPull > 0 ? Theme.Palette.accent.opacity(0.3 + leftPull * 0.7) : .white.opacity(0.1 + rightPull * 0.3)
    }

    private var glowColor: Color {
        leftPull > 0 ? Theme.Palette.accent.opacity(0.25 + leftPull * 0.45) : .black.opacity(0.5)
    }

    @ViewBuilder private var stamp: some View {
        if drag.width > 30 {
            stampLabel("Keep", icon: "checkmark", tint: nil)
                .opacity(Double(min(drag.width / 110, 1)))
        } else if drag.width < -30 {
            stampLabel(deleteLabel, icon: "trash.fill", tint: Theme.Palette.accent)
                .opacity(Double(min(-drag.width / 110, 1)))
        }
    }

    private func stampLabel(_ text: String, icon: String, tint: Color?) -> some View {
        Label(text, systemImage: icon)
            .font(Theme.Typeface.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.x5).padding(.vertical, Theme.Space.x3)
            .glassEffect(tint.map { .regular.tint($0) } ?? .regular)
            .padding(.top, Theme.Space.x5)
    }

    private var accessibilityText: String {
        var parts: [String] = [item.mediaKind == .video ? "Video" : "Photo"]
        if let date = item.creationDate { parts.append(date.formatted(date: .long, time: .omitted)) }
        if item.isFavorite { parts.append("favorite") }
        return parts.joined(separator: ", ")
    }
}

/// Label whose icon takes a graphic tint while the text stays readable.
struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

/// One big number on the end-of-deck screen.
private struct FinishStat: View {
    let value: Int
    let label: String
    let systemImage: String
    var red = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x2) {
            Group {
                if red {
                    IconTile(systemName: systemImage, size: 32)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("\(value)")
                .font(Theme.Typeface.title)
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Theme.Palette.accent.opacity(red ? 0.18 : 0.06)),
                     in: RoundedRectangle(cornerRadius: Theme.Radius.glass, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
