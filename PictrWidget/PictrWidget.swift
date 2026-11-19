import SwiftUI
import UIKit
import WidgetKit

@main
struct PictrWidgets: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
    }
}

/// Mirrors Theme.Palette and Theme.Typeface in the app. Red is for graphics only, never text.
private enum Ink {
    static let background = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255)
    static let primary = Color(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255)
    static let secondary = Color(red: 0xA8 / 255, green: 0xA8 / 255, blue: 0xA8 / 255)
    static let accent = Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
    static let accentSubtle = Color(red: 0x2A / 255, green: 0x0E / 255, blue: 0x0B / 255)

    static func display(_ size: CGFloat) -> Font { .custom("Geist-SemiBold", size: size) }
    static func number(_ size: CGFloat) -> Font { .custom("Geist-Bold", size: size).monospacedDigit() }
    static func body(_ size: CGFloat) -> Font { .custom("DMSans-9ptRegular_Medium", size: size) }
}

struct OnThisDayEntry: TimelineEntry {
    let date: Date
    /// Nil until Pictr has been opened once.
    let shown: WidgetFeed.Shown?
    let photo: UIImage?
}

struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: .now, shown: WidgetFeed.Shown(date: .now, photoCount: 14, years: 4, streak: 7,
                                                           reviewedToday: 12, queued: 4, showsPhoto: false,
                                                           isWeek: false),
                       photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        let entry = entries(from: .now).first
        completion(context.isPreview && entry?.shown == nil ? placeholder(in: context) : entry ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        let entries = entries(from: .now)
        // Nothing ahead to show: wait for Pictr to publish rather than asking again at once.
        completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never))
    }

    private func entries(from now: Date) -> [OnThisDayEntry] {
        guard let feed = WidgetFeed.load() else { return [OnThisDayEntry(date: now, shown: nil, photo: nil)] }
        let photo = WidgetFeed.photoURL.flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
        return feed.timelineDates(from: now).map { date in
            let shown = feed.shown(on: date)
            return OnThisDayEntry(date: date, shown: shown, photo: shown.showsPhoto ? photo : nil)
        }
    }
}

struct OnThisDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeed.kind, provider: OnThisDayProvider()) { entry in
            OnThisDayView(entry: entry)
                .widgetURL(URL(string: "pictr://today"))
        }
        .configurationDisplayName("On This Day")
        .description("Photos from this day in past years, and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct OnThisDayView: View {
    let entry: OnThisDayEntry
    @Environment(\.widgetFamily) private var family

    private var title: String { entry.shown?.isWeek == true ? "This week" : "On this day" }

    /// "14 photos · 4 years", or what to do when there is nothing to count.
    private var countLine: String {
        guard let shown = entry.shown, let photos = shown.photoCount else { return "Open Pictr" }
        guard photos > 0 else { return "Nothing from past years" }
        let count = photos == 1 ? "1 photo" : "\(photos) photos"
        let years = shown.years == 1 ? "1 year" : "\(shown.years) years"
        return "\(count) · \(years)"
    }

    private var streakLine: String? {
        guard let shown = entry.shown else { return nil }
        if shown.streak > 0 { return shown.streak == 1 ? "1-day streak" : "\(shown.streak)-day streak" }
        return shown.reviewedToday > 0 ? "\(shown.reviewedToday) reviewed today" : nil
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.shown?.photoCount.map { $0 > 0 ? "\(title): \(countLine)" : title } ?? title,
                  systemImage: "photo.on.rectangle")
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "photo.on.rectangle").font(.caption)
                    if let photos = entry.shown?.photoCount {
                        Text("\(photos)").font(.title3.weight(.semibold)).minimumScaleFactor(0.6)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(countLine)")
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).widgetAccentable()
                Text(countLine).font(.caption)
                if let streakLine { Text(streakLine).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // Over a photo, secondary grey can't be read against a bright sky.
                Text(title).font(Ink.body(12)).foregroundStyle(entry.photo == nil ? Ink.secondary : Ink.primary)
                Spacer()
                if let streak = entry.shown?.streak, streak > 0 { streakBadge(streak) }
            }
            Spacer()
            if entry.photo == nil, let photos = entry.shown?.photoCount, photos > 0 {
                Text("\(photos)").font(Ink.number(40)).foregroundStyle(Ink.primary)
            }
            Text(countLine).font(Ink.display(14)).foregroundStyle(Ink.primary).lineLimit(2)
        }
        .padding(14)
        .containerBackground(for: .widget) { background }
    }

    private var medium: some View {
        HStack(spacing: 0) {
            ZStack {
                Ink.accentSubtle
                if let photo = entry.photo {
                    Image(uiImage: photo).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
                        .privacySensitive()
                } else {
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(Ink.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Ink.body(12)).foregroundStyle(Ink.secondary)
                Text(entry.date.formatted(.dateTime.month(.wide).day())).font(Ink.display(18)).foregroundStyle(Ink.primary)
                Text(countLine).font(Ink.body(13)).foregroundStyle(Ink.primary).lineLimit(2)
                Spacer(minLength: 0)
                if let streakLine {
                    Label { Text(streakLine) } icon: { Image(systemName: "flame.fill").foregroundStyle(Ink.accent) }
                        .font(Ink.body(12)).foregroundStyle(Ink.secondary)
                }
                if let queued = entry.shown?.queued, queued > 0 {
                    Label { Text("\(queued) ready to delete") } icon: { Image(systemName: "trash.fill").foregroundStyle(Ink.accent) }
                        .font(Ink.body(12)).foregroundStyle(Ink.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(Ink.background, for: .widget)
    }

    /// The photo fills a small widget, darkened at the edges so the text stays readable.
    @ViewBuilder private var background: some View {
        if let photo = entry.photo {
            ZStack {
                Image(uiImage: photo).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
                    .privacySensitive()
                LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            LinearGradient(colors: [Ink.accentSubtle, Ink.background], startPoint: .topTrailing, endPoint: .bottomLeading)
        }
    }

    private func streakBadge(_ streak: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill").foregroundStyle(Ink.accent)
            Text("\(streak)").foregroundStyle(Ink.primary)
        }
        .font(Ink.number(12))
        .accessibilityLabel(streak == 1 ? "1-day streak" : "\(streak)-day streak")
    }
}
