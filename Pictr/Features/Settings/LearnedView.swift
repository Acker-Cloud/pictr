import SwiftUI

/// What Pictr has learned from your decisions, in plain facts, plus an optional
/// on-device Apple Intelligence summary.
struct LearnedView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(DecisionsModel.self) private var decisions
    @Environment(AppleIntelligence.self) private var intelligence

    private var summary: TasteSummary { library.tasteSummary }

    var body: some View {
        List {
          Group {
            Section {
                LabeledContent("Decisions", value: decisions.book.labels.count.formatted())
                LabeledContent("Photos read", value: summary.analyzedLabelCount.formatted())
                if let progress = library.learning {
                    VStack(alignment: .leading, spacing: Theme.Space.x2) {
                        Text("Reading \(progress.completed) of \(progress.total) decided photos")
                            .foregroundStyle(Theme.Palette.textPrimary)
                        ProgressBar(value: progress.fraction)
                    }
                    Button("Stop") { library.stopLearning() }
                } else {
                    Button("Update suggestions") {
                        Task { await library.updateSuggestions(labels: decisions.book.labels) }
                    }
                    .disabled(decisions.book.labels.isEmpty)
                }
            } footer: {
                Text("Pictr reads what each decided photo shows and how it looks, using Apple's on-device image models. Maybe Delete then favors photos like the ones you delete and avoids ones like those you keep.")
            }

            if intelligence.canSummarize {
                Section {
                    if let text = intelligence.summary {
                        Text(text).foregroundStyle(Theme.Palette.textPrimary)
                    } else if intelligence.isGenerating {
                        ProgressView()
                    } else if let failure = intelligence.failure {
                        Text(failure).foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Text("Needs at least one subject below.").foregroundStyle(Theme.Palette.textSecondary)
                    }
                } header: {
                    SectionLabel("Summary")
                }
            }

            Section {
                if summary.deletes.isEmpty {
                    Text(emptyText).foregroundStyle(Theme.Palette.textSecondary)
                }
                ForEach(summary.deletes, id: \.name) { SubjectRow(subject: $0) }
            } header: {
                SectionLabel("You tend to delete")
            }

            Section {
                if summary.keeps.isEmpty {
                    Text(emptyText).foregroundStyle(Theme.Palette.textSecondary)
                }
                ForEach(summary.keeps, id: \.name) { SubjectRow(subject: $0) }
            } header: {
                SectionLabel("You tend to keep")
            } footer: {
                Text("A subject appears after about 3 decided photos of it. Subjects come from Apple's classifier and can be wrong.")
            }
          }
          .listRowBackground(GlassRow())
        }
        .font(Theme.Typeface.body)
        .pictrList()
        .navigationTitle("What Pictr has learned")
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.refreshTasteSummary(labels: decisions.book.labels) }
        .task(id: summary) { await intelligence.summarize(summary) }
    }

    private var emptyText: String {
        summary.analyzedLabelCount == 0
            ? "Nothing yet. Swipe in Today or Lookback, then tap Update suggestions."
            : "No clear pattern yet."
    }
}

private struct SubjectRow: View {
    let subject: TasteSummary.Subject

    var body: some View {
        LabeledContent(subject.name.capitalized, value: "\(subject.deletes) deleted · \(subject.keeps) kept")
    }
}
