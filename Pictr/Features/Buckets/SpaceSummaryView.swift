import SwiftUI

/// Separates what moved to Recently Deleted from what isn't on this iPhone.
/// The queue total lives on the delete button. None of these is space returned to the device yet.
struct SpaceSummaryView: View {
    @Environment(LibraryModel.self) private var model
    /// Bytes of queued items stored only in iCloud.
    let queuedCloudOnlyBytes: Int64

    var body: some View {
        Panel {
        VStack(alignment: .leading, spacing: Theme.Space.x4) {
            if model.ledger.movedCount > 0 {
                row("Moved to Recently Deleted",
                    bytes: model.ledger.movedBytes,
                    note: "This session, \(model.ledger.movedCount) items. Items stored on this iPhone stay for 30 days unless you empty Recently Deleted in Photos.")
            }
            if queuedCloudOnlyBytes > 0 {
                row("Queued but not on this iPhone",
                    bytes: queuedCloudOnlyBytes,
                    note: "Stored in iCloud only. Deleting these frees iCloud storage, not this iPhone's.")
            }
        }
        }
    }

    private func row(_ title: String, bytes: Int64, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Theme.Typeface.bodyMedium)
                Spacer()
                Text(ByteFormat.string(bytes)).font(Theme.Typeface.number)
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            Text(note)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
