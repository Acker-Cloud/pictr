import AppIntents

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Review On This Day"
    static let description: IntentDescription? = IntentDescription("Opens Pictr on photos taken on this date in earlier years.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.today)
        return .result()
    }
}

struct ShuffleIntent: AppIntent {
    static let title: LocalizedStringResource = "Shuffle"
    static let description: IntentDescription? = IntentDescription("Opens a deck of random unreviewed photos from any year.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.today, shuffle: true)
        return .result()
    }
}

struct OpenCleanupIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cleanup"
    static let description: IntentDescription? = IntentDescription("Opens Pictr's cleanup suggestions.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.cleanup)
        return .result()
    }
}

struct OpenReadyToDeleteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Ready to Delete"
    static let description: IntentDescription? = IntentDescription("Opens the photos waiting for you to confirm a delete.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.queue)
        return .result()
    }
}

/// Answers without opening Pictr. Reads the saved decisions; nothing is changed.
struct ReadyToDeleteCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Ready to Delete Count"
    static let description: IntentDescription? = IntentDescription("Says how many photos wait in Ready to Delete.")
    static let supportedModes: IntentModes = .background
    /// Saved decisions can't be read before the first unlock, and this is about your photos.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    struct Unreadable: Error, CustomLocalizedStringResourceConvertible {
        var localizedStringResource: LocalizedStringResource {
            "Pictr can't read Ready to Delete right now. Open Pictr to check."
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let count = DecisionsModel.savedQueueCount() else { throw Unreadable() }
        let text = switch count {
        case 0: "Nothing is waiting in Ready to Delete."
        case 1: "1 photo is waiting in Ready to Delete. Nothing is deleted until you confirm."
        default: "\(count) photos are waiting in Ready to Delete. Nothing is deleted until you confirm."
        }
        return .result(value: count, dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
    }
}

struct PictrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenTodayIntent(),
                    phrases: ["Review On This Day in \(.applicationName)", "Open \(.applicationName) On This Day"],
                    shortTitle: "On This Day", systemImageName: "sun.horizon.fill")
        AppShortcut(intent: ShuffleIntent(),
                    phrases: ["Shuffle \(.applicationName)", "Shuffle my photos in \(.applicationName)"],
                    shortTitle: "Shuffle", systemImageName: "shuffle")
        AppShortcut(intent: OpenCleanupIntent(),
                    phrases: ["Open Cleanup in \(.applicationName)", "Clean up photos with \(.applicationName)"],
                    shortTitle: "Cleanup", systemImageName: "wand.and.sparkles")
        AppShortcut(intent: OpenReadyToDeleteIntent(),
                    phrases: ["Open Ready to Delete in \(.applicationName)"],
                    shortTitle: "Ready to Delete", systemImageName: "trash.fill")
        AppShortcut(intent: ReadyToDeleteCountIntent(),
                    phrases: ["How many photos are ready to delete in \(.applicationName)"],
                    shortTitle: "Ready to Delete Count", systemImageName: "number")
    }
}
