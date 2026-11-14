import Photos
import PhotosUI
import UIKit

@MainActor
enum LimitedLibraryPicker {
    /// Presents Apple's picker for changing the limited selection.
    static func present() async {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
