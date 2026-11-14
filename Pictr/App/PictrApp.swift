import SwiftUI

@main
struct PictrApp: App {
    @State private var library = LibraryModel(client: PhotoKitClient())
    @State private var decisions = DecisionsModel()
    @State private var viewer = ViewerPresenter()
    @State private var reminder = DailyReminder()
    @State private var intelligence = AppleIntelligence()

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(decisions)
                .environment(viewer)
                .environment(reminder)
                .environment(intelligence)
                .tint(Theme.Palette.accent)
                .preferredColorScheme(.dark)
                .fontDesign(.default)
        }
    }
}
