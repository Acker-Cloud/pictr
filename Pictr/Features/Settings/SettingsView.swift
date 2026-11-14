import SwiftUI
import UIKit

/// Every preference in one place: review pace, reminder, cleanup rules,
/// suggestions and Apple Intelligence, photo access, privacy, about.
struct SettingsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(DailyReminder.self) private var reminder
    @Environment(AppleIntelligence.self) private var intelligence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.dailyGoal) private var dailyGoal = 50
    @AppStorage(Prefs.batchSize) private var batchSize = 0
    @State private var confirmsReset = false

    private let windows = [30, 90, 365, 0]
    private let videoSizes: [Int64] = [50_000_000, 100_000_000, 250_000_000, 500_000_000]

    var body: some View {
        @Bindable var library = library
        @Bindable var intelligence = intelligence
        NavigationStack {
            Form {
                Group {
                    Section {
                        NavigationLink {
                            OverviewView()
                        } label: {
                            LabeledContent {
                                Text("\(decisions.book.reviewedCount(on: .now)) of \(dailyGoal) today")
                            } label: {
                                RowLabel("Progress", systemImage: "chart.bar.fill")
                            }
                        }
                    } footer: {
                        Text("Streaks, the last two weeks, totals, Cleanup Plan, achievements and history.")
                    }

                    Section {
                        AppIconPicker()
                    } header: {
                        SectionLabel("App icon")
                    }

                    Section {
                        Picker(selection: $dailyGoal) {
                            ForEach(Prefs.dailyGoals, id: \.self) { Text("\($0) photos").tag($0) }
                        } label: {
                            RowLabel("Daily goal", systemImage: "target")
                        }
                        Picker(selection: $batchSize) {
                            ForEach(Prefs.batchSizes, id: \.self) { Text(Prefs.batchLabel($0)).tag($0) }
                        } label: {
                            RowLabel("Photos per deck", systemImage: "rectangle.stack.fill")
                        }
                    } header: {
                        SectionLabel("Reviewing")
                    } footer: {
                        Text("A shorter deck is easier to finish. Open it again to pick up where you stopped.")
                    }

                    Section {
                        Toggle(isOn: reminderEnabled) { RowLabel("Daily reminder", systemImage: "bell.fill") }
                            .tint(Theme.Palette.accent)
                        if reminder.isEnabled {
                            DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                                RowLabel("Time", systemImage: "clock.fill")
                            }
                        }
                        if reminder.isDenied {
                            Button { openAppSettings() } label: {
                                RowLabel("Allow notifications in Settings", systemImage: "exclamationmark.bubble.fill")
                            }
                        }
                    } header: {
                        SectionLabel("Reminder")
                    } footer: {
                        Text(reminderFooter)
                    }

                    Section {
                        Picker(selection: $library.settings.windowDays) {
                            ForEach(windows, id: \.self) { Text(windowLabel($0)).tag($0) }
                        } label: {
                            RowLabel("Look back", systemImage: "calendar")
                        }
                        Picker(selection: $library.settings.blur) {
                            ForEach(BlurSensitivity.allCases) { Text($0.title).tag($0) }
                        } label: {
                            RowLabel("Blurry", systemImage: "camera.aperture")
                        }
                        Picker(selection: $library.settings.largeVideoBytes) {
                            ForEach(videoSizes, id: \.self) { Text("\(ByteFormat.string($0)) or more").tag($0) }
                        } label: {
                            RowLabel("Large video", systemImage: "video.fill")
                        }
                    } header: {
                        SectionLabel("Cleanup")
                    } footer: {
                        Text("Look back sets which photos Cleanup checks. A longer window takes longer to analyze. Blur scores are estimates, so look before deleting.")
                    }

                    Section {
                        NavigationLink {
                            LearnedView()
                        } label: {
                            LabeledContent {
                                Text("\(decisions.book.labels.count)")
                            } label: {
                                RowLabel("What Pictr has learned", systemImage: "brain.head.profile")
                            }
                        }
                        Toggle(isOn: $intelligence.isEnabled) {
                            RowLabel("Apple Intelligence summary", systemImage: "apple.intelligence")
                        }
                        .tint(Theme.Palette.accent)
                        .disabled(intelligence.status != .available && !intelligence.isEnabled)
                        Button { confirmsReset = true } label: {
                            RowLabel("Reset learning", systemImage: "arrow.counterclockwise")
                        }
                        .confirmationDialog("Reset learning?", isPresented: $confirmsReset, titleVisibility: .visible) {
                            Button("Reset learning", role: .destructive) {
                                decisions.forgetLearning()
                                Task { await library.resetLearning(labels: decisions.book.labels) }
                            }
                        } message: {
                            Text("Forgets Teach answers, deleted-photo examples and what Pictr read from your photos. Your keep and delete decisions and Ready to Delete stay.")
                        }
                    } header: {
                        SectionLabel("Suggestions")
                    } footer: {
                        Text("\(intelligence.statusText) The summary uses Apple's on-device model only. Suggestions themselves never need Apple Intelligence.")
                    }

                    Section {
                        LabeledContent {
                            Text(accessLabel)
                        } label: {
                            RowLabel("Access", systemImage: "photo.on.rectangle.angled")
                        }
                        if library.authState == .limited {
                            Button { Task { await LimitedLibraryPicker.present() } } label: {
                                RowLabel("Choose photos", systemImage: "checklist")
                            }
                        }
                        Button { openAppSettings() } label: {
                            RowLabel("Change in Settings", systemImage: "gearshape.fill")
                        }
                    } header: {
                        SectionLabel("Photos")
                    } footer: {
                        Text("Pictr has no network code. Photos, decisions and what it learns stay on this iPhone. Deleting always goes through Apple's confirmation, and photos wait in Recently Deleted for 30 days.")
                    }

                    Section {
                        LabeledContent {
                            Text(version)
                        } label: {
                            RowLabel("Version", systemImage: "info")
                        }
                        NavigationLink { AcknowledgementsView() } label: {
                            RowLabel("Acknowledgements", systemImage: "text.book.closed.fill")
                        }
                    } header: {
                        SectionLabel("About")
                    }
                }
                .listRowBackground(GlassRow())
            }
            .tint(Theme.Palette.textPrimary)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .pictrList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reminder.refreshPermission() }
            .onChange(of: reminder.minutes) { Task { await reschedule() } }
        }
    }

    private var reminderEnabled: Binding<Bool> {
        Binding { reminder.isEnabled } set: { on in
            Task {
                if on { _ = await reminder.enable() } else { reminder.isEnabled = false }
                await reschedule()
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminder.minutes / 60, minute: reminder.minutes % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminder.minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
    }

    private var reminderFooter: String {
        if reminder.isDenied { return "Notifications are off for Pictr." }
        guard reminder.isEnabled else {
            return "One notification a day, only on days with photos from past years."
        }
        return switch reminder.scheduledCount {
        case 0: "No days in the next two weeks have photos from past years."
        case 1: "1 reminder set for the next two weeks."
        default: "\(reminder.scheduledCount) reminders set for the next two weeks."
        }
    }

    private var accessLabel: String {
        switch library.authState {
        case .authorized: "All photos"
        case .limited: "Selected photos"
        case .denied, .restricted: "None"
        case .notDetermined: "Not asked"
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func reschedule() async {
        await reminder.reschedule(client: library.client, decided: decisions.book.decidedIDs)
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("Geist by Vercel and DM Sans by Colophon Foundry are used under the SIL Open Font License 1.1. The licence texts ship inside the app.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .font(Theme.Typeface.body)
        .pictrList()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
