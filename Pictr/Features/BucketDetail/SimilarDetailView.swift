import SwiftUI

/// Similar-shot sets. Each set's keeper is protected; the rest start selected.
struct SimilarDetailView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    @State private var chosen: Set<String>?
    @State private var thumbnails = ThumbnailProvider()
    @State private var comparing: SimilarGroup?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    private var cellPixels: CGSize { CGSize(width: 130 * displayScale, height: 130 * displayScale) }

    private var bucketSet: BucketSet { model.buckets.excluding(decisions.book.decidedIDs) }
    private var groups: [SimilarGroup] { bucketSet.similarGroups }
    private var members: [String: BucketMember] {
        Dictionary(bucketSet[.similar].members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var extras: [BucketMember] { groups.flatMap(\.extraIDs).compactMap { members[$0] } }
    private func isSelected(_ id: String) -> Bool { chosen?.contains(id) ?? true }
    private var selected: [BucketMember] { extras.filter { isSelected($0.id) } }
    private var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size.bytes } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.x6) {
                Text(BucketKind.similar.reason)
                    .font(Theme.Typeface.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Space.x4)

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Theme.Space.x2) {
                        HStack {
                            Eyebrow("\(group.memberIDs.count) shots")
                            Spacer()
                            Button("Compare", systemImage: "rectangle.split.1x2") { comparing = group }
                                .font(Theme.Typeface.captionMedium)
                                .buttonStyle(.glass)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .padding(.horizontal, Theme.Space.x4)

                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(group.memberIDs, id: \.self) { id in
                                if group.keeperIDs.contains(id) {
                                    KeeperCell(id: id, provider: thumbnails, pixels: cellPixels.width)
                                        .onTapGesture { viewer.open(group.memberIDs, at: group.memberIDs.firstIndex(of: id) ?? 0) }
                                } else if let member = members[id] {
                                    ThumbnailCell(member: member, isSelected: isSelected(id), showsSize: false,
                                                  provider: thumbnails, targetSize: cellPixels)
                                        .onTapGesture { toggle(id) }
                                        .photoContextMenu(id: id, in: group.memberIDs, presenter: viewer,
                                                          decisions: decisions, provider: thumbnails)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Space.x2)
        }
        .background(PictrBackground())
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(BucketKind.similar.title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsToolbar()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.x2) {
                Button {
                    decisions.queue(ids: selected.map(\.id))
                    chosen = nil
                } label: {
                    Text("Add \(selected.count) to Ready to Delete (\(ByteFormat.string(selectedBytes)))")
                        .frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .disabled(selected.isEmpty)
                Text("Keepers stay. Nothing is deleted until you confirm in Ready to Delete.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(Theme.Space.x4)
        }
        .sheet(item: $comparing) { group in
            CompareView(group: group)
        }
        .onAppear { thumbnails.prepare(ids: groups.flatMap(\.memberIDs), targetSize: cellPixels) }
        .onDisappear { thumbnails.stop() }
    }

    private func toggle(_ id: String) {
        var set = chosen ?? Set(extras.map(\.id))
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        chosen = set
    }
}

private struct KeeperCell: View {
    let id: String
    let provider: ThumbnailProvider
    let pixels: CGFloat

    var body: some View {
        Thumb(id: id, provider: provider, pixels: pixels)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Label("Keeper", systemImage: "star.fill")
                    .font(Theme.Typeface.captionMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.x2).padding(.vertical, Theme.Space.x1)
                    .glassEffect()
                    .padding(6)
            }
            .overlay(Rectangle().stroke(Theme.Palette.textPrimary.opacity(0.6), lineWidth: 2))
            .accessibilityElement()
            .accessibilityLabel("Keeper, protected")
    }
}

/// Keeper on top, another shot below. With Zoom Lock on, pinching or panning one
/// moves both, so details line up.
struct CompareView: View {
    let group: SimilarGroup

    @Environment(DecisionsModel.self) private var decisions
    @Environment(\.dismiss) private var dismiss
    @State private var loader = ImageLoader()
    @State private var otherIndex = 0
    @State private var zoomLock = true
    @State private var shared = ZoomState()
    @State private var top = ZoomState()
    @State private var bottom = ZoomState()

    private var keeper: String { group.memberIDs.first { group.keeperIDs.contains($0) } ?? group.memberIDs[0] }
    private var others: [String] {
        group.memberIDs.filter { $0 != keeper && decisions.book.decision(for: $0) == nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 2) {
                pane(id: keeper, label: "Keeper", state: zoomLock ? $shared : $top)
                if others.indices.contains(otherIndex) {
                    pane(id: others[otherIndex], label: "\(otherIndex + 1) of \(others.count)",
                         state: zoomLock ? $shared : $bottom)
                } else {
                    Theme.Palette.bgDeep.overlay {
                        Text("No other shots left in this set.")
                            .font(Theme.Typeface.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
            .background(Color.black)
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $zoomLock) { Label("Zoom Lock", systemImage: zoomLock ? "lock.fill" : "lock.open") }
                        .toggleStyle(.button)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: Theme.Space.x4) {
            HStack(spacing: Theme.Space.x4) {
                Button { otherIndex = max(otherIndex - 1, 0) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .disabled(otherIndex == 0)
                .accessibilityLabel("Previous shot")

                Button {
                    guard others.indices.contains(otherIndex) else { return }
                    decisions.queue(ids: [others[otherIndex]])
                    otherIndex = min(otherIndex, max(others.count - 1, 0))
                } label: {
                    Label("Add to Ready to Delete", systemImage: "trash.fill")
                }
                .primaryGlassButton()
                .disabled(others.isEmpty)

                Button { otherIndex = min(otherIndex + 1, max(others.count - 1, 0)) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .disabled(otherIndex >= others.count - 1)
                .accessibilityLabel("Next shot")
            }
            .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(Theme.Space.x4)
    }

    private func pane(id: String, label: String, state: Binding<ZoomState>) -> some View {
        ZoomPane(id: id, loader: loader, state: state)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(Theme.Typeface.captionMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.x3).padding(.vertical, Theme.Space.x1 + 2)
                    .glassEffect()
                    .padding(Theme.Space.x3)
            }
    }
}

struct ZoomState: Equatable {
    var scale: CGFloat = 1
    var lastScale: CGFloat = 1
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
}

private struct ZoomPane: View {
    let id: String
    let loader: ImageLoader
    @Binding var state: ZoomState
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(state.scale)
                        .offset(state.offset)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { state.scale = min(max(state.lastScale * $0.magnification, 1), 6) }
                    .onEnded { _ in
                        state.lastScale = state.scale
                        if state.scale <= 1 { state.offset = .zero; state.lastOffset = .zero }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard state.scale > 1 else { return }
                            state.offset = CGSize(width: state.lastOffset.width + value.translation.width,
                                                  height: state.lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in state.lastOffset = state.offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(Theme.Motion.slow) {
                    if state.scale > 1 { state = ZoomState() } else { state.scale = 2.5; state.lastScale = 2.5 }
                }
            }
            .task(id: id) {
                image = nil
                let pixels = CGSize(width: geo.size.width * displayScale * 2.5, height: geo.size.height * displayScale * 2.5)
                for await next in loader.images(for: id, targetSize: pixels) { image = next }
            }
        }
    }
}
