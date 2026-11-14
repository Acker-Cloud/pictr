import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DecisionsModel.self) private var decisions
    @Environment(ViewerPresenter.self) private var viewer
    @Environment(DailyReminder.self) private var reminder
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.authState {
            case .authorized, .limited:
                TabView {
                    Tab("Today", systemImage: "sun.horizon.fill") { TodayView() }
                    Tab("Lookback", systemImage: "clock.arrow.circlepath") { LookbackView() }
                    Tab("Cleanup", systemImage: "wand.and.sparkles") { BucketListView() }
                    Tab("Ready to Delete", systemImage: "trash.fill") { ReadyToDeleteView() }
                        .badge(decisions.queueCount)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                // Selected tab labels are text: white, not red (red is 3.2:1).
                .tint(Theme.Palette.textPrimary)
            case .notDetermined, .denied, .restricted:
                AccessView()
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Counts change as you review and as the date moves; re-plan on every foreground.
            guard phase == .active, reminder.isEnabled else { return }
            Task {
                await reminder.refreshPermission()
                await reminder.reschedule(client: model.client, decided: decisions.book.decidedIDs)
            }
        }
        .fullScreenCover(item: Binding(get: { viewer.request }, set: { viewer.request = $0 })) { request in
            PhotoViewer(request: request)
        }
    }
}
