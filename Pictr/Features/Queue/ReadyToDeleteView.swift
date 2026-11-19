import SwiftUI

/// Everything swiped left or added from Cleanup. Deleting is a separate,
/// system-confirmed step.
struct ReadyToDeleteView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(\.displayScale) private var displayScale
    @State private var members: [BucketMember] = []
    @State private var loading = false
    @State private var thumbnails = ThumbnailProvider()

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]
    private var cellPixels: CGSize { CGSize(width: 130 * displayScale, height: 130 * displayScale) }
    private var totalBytes: Int64 { members.reduce(0) { $0 + $1.size.bytes } }
    private var cloudOnlyBytes: Int64 {
        members.filter { $0.availability == .cloudOnly }.reduce(0) { $0 + $1.size.bytes }
    }
    private var hasEstimates: Bool { members.contains { $0.size.isEstimated } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.x4) {
                    if library.ledger.movedCount > 0 || cloudOnlyBytes > 0 {
                        SpaceSummaryView(queuedCloudOnlyBytes: cloudOnlyBytes)
                    }
                    Text(members.isEmpty
                         ? "Swipe left in Today or Lookback, or add items from Cleanup. Nothing is deleted until you confirm."
                         : "Tap a photo to look closer. Tap its minus to take it back. Favorites are never added here.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(Theme.Space.x4)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(members) { member in
                        ThumbnailCell(member: member, isSelected: true, isRemovable: true, showsSize: false,
                                      provider: thumbnails, targetSize: cellPixels)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(Theme.Motion.base) {
                                        decisions.unqueue([member.id])
                                        members.removeAll { $0.id == member.id }
                                    }
                                } label: {
                                    Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Take back")
                            }
                            .accessibilityHint("Opens the photo")
                            .accessibilityIdentifier("queued-photo")
                            .onTapGesture { viewer.open(members.map(\.id), at: members.firstIndex { $0.id == member.id } ?? 0) }
                            .photoContextMenu(id: member.id, in: members.map(\.id), presenter: viewer,
                                              decisions: decisions, provider: thumbnails)
                    }
                }
            }
            .background(PictrBackground())
            .pageHeader("Ready to Delete")
            .safeAreaInset(edge: .bottom) {
                if !members.isEmpty { deleteBar }
            }
            .overlay { if loading && members.isEmpty { ProgressView() } }
            .task(id: decisions.book.queue) { await load() }
            .sensoryFeedback(.impact(weight: .light), trigger: members.count)
        }
    }

    private var deleteBar: some View {
        VStack(spacing: Theme.Space.x2) {
            Button {
                Task { await apply() }
            } label: {
                HStack(spacing: 6) {
                    if library.isDeleting { ProgressView() }
                    Text("Delete \(members.count) (\(ByteFormat.string(totalBytes)))")
                    if hasEstimates { Text("est.").font(.caption.weight(.semibold)) }
                }
                .frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
            .disabled(library.isDeleting)

            Text("Apple will ask you to confirm. Items go to Recently Deleted for 30 days.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Space.x4)
    }

    private func load() async {
        let ids = decisions.book.queue
        guard !ids.isEmpty else { members = []; loading = false; return }
        loading = true
        let client = library.client
        let found = await Task.detached(priority: .userInitiated) { client.members(for: ids) }.value
        // A newer load started when the queue changed; this one's result is out of date.
        guard !Task.isCancelled else { return }
        // Keep queue order.
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        members = ids.compactMap { byID[$0] }
        loading = false
        thumbnails.prepare(ids: members.map(\.id), targetSize: cellPixels)
    }

    private func apply() async {
        let batch = members
        let outcome = await library.delete(batch) { decisions.book.queuedIDs }
        // A favorite never stays queued, however it got there.
        decisions.unqueue(decisions.book.queue.filter { library.knownFavorites[$0] == true })
        guard case let .deleted(submitted)? = outcome else { return }
        let bytes = batch.filter { submitted.contains($0.id) }.reduce(0) { $0 + $1.size.bytes }
        // Clear what was deleted and what Photos no longer has. Anything taken back or
        // queued while Apple's sheet was up stays as it is.
        let queue = decisions.book.queue
        let client = library.client
        let present = await Task.detached(priority: .userInitiated) { Set(client.members(for: queue).map(\.id)) }.value
        let settled = queue.filter { submitted.contains($0) || !present.contains($0) }
        decisions.finishApply(queued: settled, submitted: submitted, bytes: bytes)
    }
}
