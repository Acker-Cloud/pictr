import SwiftUI

/// Start, pause and resume on-device analysis. Nothing scans automatically.
struct AnalysisPanel: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DecisionsModel.self) private var decisions
    @State private var training: [ReviewItem]?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x3) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("On-device analysis")
                Spacer()
                if model.analyzedCount > 0 {
                    Text("\(model.analyzedCount) analyzed")
                        .font(Theme.Typeface.number)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            switch model.analysisState {
            case let .running(progress):
                Text("Checking \(progress.completed) of \(progress.total)")
                    .font(Theme.Typeface.bodyMedium)
                    .foregroundStyle(Theme.Palette.textPrimary)
                ProgressBar(value: progress.fraction)
                Button { model.pauseAnalysis() } label: {
                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
            case .idle:
                Text(message)
                    .font(Theme.Typeface.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if model.pendingAnalysisCount > 0 {
                    Button { model.startAnalysis() } label: {
                        Label(model.analyzedCount == 0 ? "Analyze \(model.pendingAnalysisCount) photos"
                                                       : "Resume: \(model.pendingAnalysisCount) left",
                              systemImage: "sparkle.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryGlassButton()
                    .disabled(model.phase != .ready)
                }
                if model.analyzedCount > 0 { taste }
            }
        }
        .padding(.vertical, Theme.Space.x1)
        .navigationDestination(item: $training) { items in
            DeckView(title: "Teach your taste", items: items, mode: .train)
        }
    }

    @ViewBuilder private var taste: some View {
        Divider().padding(.vertical, Theme.Space.x1)
        Eyebrow("Your taste")
        Text(tasteMessage)
            .font(Theme.Typeface.callout)
            .foregroundStyle(Theme.Palette.textSecondary)
        HStack(spacing: Theme.Space.x2) {
            Button {
                Task { training = await model.trainingItems(labels: decisions.book.labels) }
            } label: {
                Label("Teach", systemImage: "hand.draw").frame(maxWidth: .infinity)
            }
            .secondaryGlassButton()

            if model.learning != nil {
                Button { model.stopLearning() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
            } else {
                Button {
                    Task { await model.updateSuggestions(labels: decisions.book.labels) }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .disabled(decisions.book.labels.isEmpty)
            }
        }
        if let progress = model.learning {
            Text("Reading \(progress.completed) of \(progress.total) decided photos")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            ProgressBar(value: progress.fraction)
        }
    }

    private var tasteMessage: String {
        let labels = decisions.book.labels.count
        if model.tasteTrainedOn != nil {
            return "Maybe Delete uses all \(labels) of your decisions: what those photos show and how they look. Teach adds quick answers; Update re-reads and refreshes."
        }
        return "Every keep and delete in Today, Lookback and Teach counts. Update reads what those photos show and how they look, then fills Maybe Delete with photos like the ones you delete."
    }

    private var message: String {
        if model.pendingAnalysisCount == 0 && model.analyzedCount > 0 {
            return "Up to date. Similar shots, blurry, low-quality and utility photos are sorted below."
        }
        return "Finds similar shots, blurry photos, low-quality and utility shots. Runs on this iPhone, reads only photos stored here, and you can pause any time."
    }
}
