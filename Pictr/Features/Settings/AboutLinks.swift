import Foundation

/// Where Pictr lives outside the app. Opening one hands the URL to Safari;
/// Pictr itself makes no network request.
enum AboutLinks {
    static let home = URL(string: "https://acker.cloud/pictr")!
    static let privacy = URL(string: "https://acker.cloud/pictr/privacy")!
    static let terms = URL(string: "https://acker.cloud/pictr/terms")!
    static let help = URL(string: "https://acker.cloud/pictr/help")!
    static let source = URL(string: "https://github.com/Acker-Cloud/pictr")!
    static let issues = URL(string: "https://github.com/Acker-Cloud/pictr/issues")!
    static let license = URL(string: "https://github.com/Acker-Cloud/pictr/blob/main/LICENSE")!
    static let support = URL(string: "mailto:support@acker.cloud")!
}
