import SwiftUI

struct BucketDetailView: View {
    let kind: BucketKind

    @Environment(LibraryModel.self) private var model
    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    /// Nothing starts selected: suggestions are estimates, so you pick what goes.
    private var chosen: Set<String>? {
        get { model.selections[kind] }
        nonmutating set { model.selections[kind] = newValue }
    }
    @State private var thumbnails = ThumbnailProvider()
    @State private var reviewing = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    private var cellPixels: CGSize { CGSize(width: 130 * displayScale, height: 130 * displayScale) }

    private var bucket: Bucket { model.buckets.excluding(decisions.book.decidedIDs, queued: decisions.book.queuedIDs)[kind] }
    private func isSelected(_ id: String) -> Bool { chosen?.contains(id) ?? false }
    private var selected: [BucketMember] { bucket.members.filter { isSelected($0.id) } }
    private var allSelected: Bool { !bucket.members.isEmpty && selected.count == bucket.members.count }
    private var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size.bytes } }
    private var selectedHasEstimates: Bool { selected.contains { $0.size.isEstimated } }

    var body: some View {
        ScrollView {
            Text(kind.reason + " Tap to select, touch and hold to look closer.")
                .font(Theme.Typeface.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(bucket.members) { member in
                    ThumbnailCell(
                        member: member,
                        isSelected: isSelected(member.id),
                        showsSize: kind == .largeVideos,
                        provider: thumbnails,
                        targetSize: cellPixels,
                        caption: kind == .maybeDelete ? model.buckets.reasons[member.id] : nil
                    )
                    .onTapGesture { toggle(member.id) }
                    .photoContextMenu(id: member.id, in: bucket.members.map(\.id), presenter: viewer,
                                      decisions: decisions, provider: thumbnails)
                }
            }
        }
        .background(PictrBackground())
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Select none" : "Select all") {
                    chosen = allSelected ? [] : Set(bucket.members.map(\.id))
                }
                .disabled(bucket.members.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) { deleteBar }
        .navigationDestination(isPresented: $reviewing) {
            BucketDeck(title: kind.title, ids: bucket.members.map(\.id))
        }
        .onAppear { thumbnails.prepare(ids: bucket.members.map(\.id), targetSize: cellPixels) }
        .onDisappear { thumbnails.stop() }
    }

    private var deleteBar: some View {
        VStack(spacing: Theme.Space.x2) {
            Button { reviewing = true } label: {
                Label("Review \(bucket.count)", systemImage: "rectangle.stack.fill")
                    .frame(maxWidth: .infinity)
            }
            .secondaryGlassButton()
            .disabled(bucket.members.isEmpty)

            Button {
                decisions.queue(ids: selected.map(\.id))
                chosen = []
            } label: {
                HStack(spacing: 6) {
                    Text("Add \(selected.count) to Ready to Delete (\(ByteFormat.string(selectedBytes)))")
                    if selectedHasEstimates { Text("est.").font(.caption.weight(.semibold)) }
                }
                .frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
            .disabled(selected.isEmpty)

            Text("Nothing is deleted yet. Confirm from Ready to Delete.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Space.x4)
    }

    private func toggle(_ id: String) {
        var set = chosen ?? []
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        chosen = set
    }
}

/// Swipe deck over a suggestion's photos, in the suggestion's order.
struct BucketDeck: View {
    let title: String
    let ids: [String]

    @Environment(LibraryModel.self) private var model

    var body: some View {
        let client = model.client
        let ids = ids
        DeckLoaderView(title: title, load: { client.reviewItems(ids: ids) }, showsQuickSelect: false)
    }
}
