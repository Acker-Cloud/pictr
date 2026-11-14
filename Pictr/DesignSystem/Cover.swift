import SwiftUI
import UIKit

/// The first candidate that's stored on this iPhone, so iCloud-only photos
/// don't leave a blank cover. Never downloads.
struct Cover: View {
    let ids: [String]
    let provider: ThumbnailProvider
    let pixels: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .allowsHitTesting(false)
                } else {
                    Theme.Palette.surfaceRaised
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: ids) {
                image = nil
                let size = CGSize(width: pixels, height: pixels)
                for id in ids {
                    let thumbnail = await provider.thumbnail(for: id, targetSize: size)
                    if let found = thumbnail.image, !thumbnail.isInCloud {
                        image = found
                        return
                    }
                }
            }
    }
}
