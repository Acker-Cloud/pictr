import SwiftUI

struct ThumbnailCell: View {
    let member: BucketMember
    let isSelected: Bool
    /// Shows a remove control instead of a selection check.
    var isRemovable = false
    let showsSize: Bool
    let provider: ThumbnailProvider
    let targetSize: CGSize
    var caption: String? = nil

    @State private var thumbnail: Thumbnail?

    private var notOnDevice: Bool {
        member.availability == .cloudOnly || thumbnail?.isInCloud == true
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = thumbnail?.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        // Fill overflows the cell; only the visible cell takes touches.
                        .allowsHitTesting(false)
                } else {
                    Rectangle().fill(Theme.Palette.surface)
                        .overlay {
                            Image(systemName: notOnDevice ? "icloud" : "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if isRemovable {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: 26, height: 26)
                        .glassEffect(.regular, in: .circle)
                        .padding(6)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Theme.Palette.accent : Color.black.opacity(0.35))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if notOnDevice {
                        Label("Not on this iPhone", systemImage: "icloud")
                            .labelStyle(.iconOnly)
                    }
                    if let caption {
                        Text(caption).lineLimit(2)
                    }
                    if showsSize {
                        Text(ByteFormat.string(member.size.bytes) + (member.size.isEstimated ? " est." : ""))
                    }
                }
                .font(Theme.Typeface.captionMedium)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(6)
            }
            .opacity(isSelected || isRemovable ? 1 : 0.55)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected && !isRemovable ? [.isButton, .isSelected] : .isButton)
            .task(id: member.id) {
                thumbnail = await provider.thumbnail(for: member.id, targetSize: targetSize)
            }
    }

    private var accessibilityText: String {
        var parts = [ByteFormat.string(member.size.bytes)]
        if member.size.isEstimated { parts.append("estimated") }
        if notOnDevice { parts.append("not on this iPhone") }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }
}
