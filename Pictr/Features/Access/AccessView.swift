import SwiftUI

struct AccessView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x6) {
            Spacer()
            PictrMark(size: 140)
                .frame(maxWidth: .infinity)
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Space.x3) {
                Eyebrow(eyebrow)
                Text(title)
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(message)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
        }
        .padding(Theme.Space.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(PictrBackground())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshAccess() } }
        }
    }

    private var eyebrow: String {
        switch model.authState {
        case .notDetermined: "Pictr"
        case .denied: "Access off"
        case .restricted: "Restricted"
        case .authorized, .limited: ""
        }
    }

    private var title: String {
        switch model.authState {
        case .notDetermined: "Your past, one swipe at a time"
        case .denied: "Photo access is off"
        case .restricted: "Photo access is restricted"
        case .authorized, .limited: ""
        }
    }

    private var message: String {
        switch model.authState {
        case .notDetermined:
            "See photos from this day in past years, sweep your library month by month, and clear screenshots, burst extras and large videos. Everything stays on this iPhone. Nothing is deleted until you confirm with Apple's prompt."
        case .denied:
            "Pictr needs full library access to show your past photos and suggest deletions. Turn it on in Settings, Privacy & Security, Photos."
        case .restricted:
            "Screen Time or a device management profile limits Photos on this iPhone. Pictr can't read your library until that restriction is lifted."
        case .authorized, .limited:
            ""
        }
    }

    @ViewBuilder private var action: some View {
        switch model.authState {
        case .notDetermined:
            Button { Task { await model.requestAccess() } } label: {
                Text("Allow photo access").frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
        case .denied:
            Button { LimitedLibraryPicker.openSettings() } label: {
                Text("Open Settings").frame(maxWidth: .infinity)
            }
            .primaryGlassButton()
        case .restricted, .authorized, .limited:
            EmptyView()
        }
    }
}

/// Shown above lists when access is limited.
struct LimitedAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x2) {
            Label("Limited access", systemImage: "exclamationmark.triangle")
                .font(Theme.Typeface.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("You've shared only some photos, so most of your library won't appear here. Full access works best, and nothing leaves this iPhone either way.")
                .font(Theme.Typeface.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.x2) {
                Button("Allow full access") { LimitedLibraryPicker.openSettings() }
                    .primaryGlassButton()
                    .controlSize(.regular)
                Button("Change selection") { Task { await LimitedLibraryPicker.present() } }
                    .secondaryGlassButton()
                    .controlSize(.regular)
            }
        }
        .padding(.vertical, Theme.Space.x1)
    }
}
