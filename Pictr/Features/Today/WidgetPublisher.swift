import Foundation
import UIKit
import WidgetKit

/// Keeps the widget's feed current. Counts and today's photo are worked out when Today
/// loads; the streak, today's count and the queue whenever Pictr leaves the screen or a
/// delete is confirmed.
@MainActor
enum WidgetPublisher {
    /// Bumped by each publish, so a slower, older one can't overwrite a newer one.
    private static var generation = 0

    static func publish(today items: [ReviewItem], range: OnThisDayRange, client: any PhotoLibraryClient,
                        decisions: DecisionsModel) async {
        generation += 1
        let mine = generation
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Never a photo waiting in Ready to Delete or already deleted.
        let excluded = decisions.book.queuedIDs.union(decisions.book.deleted)
        let candidates = Array(items.filter { $0.mediaKind == .image && !excluded.contains($0.id) }.prefix(6).map(\.id))
        let (days, photo) = await Task.detached(priority: .utility) { () -> ([WidgetFeed.Day], (id: String, data: Data)?) in
            var days = [WidgetFeed.Day(day: WidgetFeed.DayKey(today, calendar: calendar), photoCount: items.count,
                                       years: distinctYears(items, calendar))]
            if let earliest = client.earliestAssetDate() {
                let earliestYear = calendar.component(.year, from: earliest)
                for offset in 1..<WidgetFeed.horizon {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                    let windows = OnThisDay.windows(on: date, earliestYear: earliestYear, range: range, calendar: calendar)
                    let found = windows.isEmpty ? [] : client.reviewItems(in: windows)
                    days.append(WidgetFeed.Day(day: WidgetFeed.DayKey(date, calendar: calendar), photoCount: found.count,
                                               years: distinctYears(found, calendar)))
                }
            }
            // The first of today's photos stored on this iPhone. Small enough for any widget
            // size, and iCloud originals are never fetched for it.
            let photo = candidates.lazy.compactMap { id in
                client.analysisImage(for: id, maxPixels: 500)
                    .flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) }
                    .map { (id: id, data: $0) }
            }.first
            return (days, photo)
        }.value
        guard mine == generation else { return }

        var feed = WidgetFeed.load() ?? WidgetFeed()
        feed.days = days
        feed.isWeek = range == .week
        if let photo, let url = WidgetFeed.photoURL, (try? photo.data.write(to: url, options: .atomic)) != nil {
            feed.photoDay = WidgetFeed.DayKey(today, calendar: calendar)
            feed.photoID = photo.id
        } else {
            dropPhoto(&feed)
        }
        update(&feed, from: decisions)
        feed.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
    }

    /// Cheap: no Photos work. Does nothing until Today has published once.
    static func publishStats(from decisions: DecisionsModel) {
        guard var feed = WidgetFeed.load() else { return }
        let before = feed
        update(&feed, from: decisions)
        guard feed != before else { return }
        feed.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.kind)
    }

    private static func update(_ feed: inout WidgetFeed, from decisions: DecisionsModel) {
        // A book that couldn't be read yet is an empty placeholder; don't publish its zeros.
        guard decisions.isLoaded else { return }
        let book = decisions.book
        let now = Date.now
        feed.streak = book.streak(endingOn: now)
        feed.reviewedToday = book.reviewedCount(on: now)
        feed.statsDay = WidgetFeed.DayKey(now)
        feed.queued = book.queue.count
        // The photo goes once it is queued or deleted, or its day has passed.
        if let id = feed.photoID,
           book.queuedIDs.contains(id) || book.deleted.contains(id) || feed.photoDay != WidgetFeed.DayKey(now) {
            dropPhoto(&feed)
        }
    }

    private static func dropPhoto(_ feed: inout WidgetFeed) {
        feed.photoDay = nil
        feed.photoID = nil
        if let url = WidgetFeed.photoURL { try? FileManager.default.removeItem(at: url) }
    }

    private nonisolated static func distinctYears(_ items: [ReviewItem], _ calendar: Calendar) -> Int {
        Set(items.compactMap { $0.creationDate.map { calendar.component(.year, from: $0) } }).count
    }
}
