import Foundation

/// Features describing why a photo might be deletable. Each is scaled to roughly 0...1,
/// except `subject` and `lookalike`, which run -1 (you keep these) to 1 (you delete these).
enum TasteFeature: Int, CaseIterable, Sendable {
    case lowQuality, utility, soft, screenshot, similarExtra, burstExtra, video, longVideo, old, lowResolution
    /// What the photo shows, scored against subjects you've deleted and kept.
    case subject
    /// How the photos that look most like it were decided.
    case lookalike

    /// Why this feature pushed a photo toward Maybe Delete. Shown to the user.
    var reason: String {
        switch self {
        case .lowQuality: "Rated low on quality"
        case .utility: "Looks like a document or receipt"
        case .soft: "Soft focus"
        case .screenshot: "Screenshot"
        case .similarExtra: "A better similar shot exists"
        case .burstExtra: "Extra burst frame"
        case .video: "Video"
        case .longVideo: "Long video"
        case .old: "Old and unreviewed"
        case .lowResolution: "Low resolution"
        case .subject: "Like photos you delete"
        case .lookalike: "Looks like photos you've deleted"
        }
    }

    /// Starting weights before any training: what most people delete.
    var prior: Double {
        switch self {
        case .lowQuality: 2.5
        case .utility: 2.0
        case .soft: 2.0
        case .screenshot: 1.5
        case .similarExtra: 2.0
        case .burstExtra: 2.0
        case .video: 0
        case .longVideo: 0.5
        case .old: 0.3
        case .lowResolution: 1.0
        case .subject: 2.5
        case .lookalike: 2.5
        }
    }

    static func vector(
        _ descriptor: any AssetDescriptor,
        analysis: AssetAnalysis?,
        isSimilarExtra: Bool,
        isBurstExtra: Bool,
        subject: Double = 0,
        lookalike: Double = 0,
        now: Date = .now
    ) -> [Double] {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        var x = [Double](repeating: 0, count: allCases.count)
        if let score = analysis?.aestheticScore { x[lowQuality.rawValue] = clamp((0.2 - Double(score)) / 1.2) }
        x[utility.rawValue] = analysis?.isUtility == true ? 1 : 0
        if let sharpness = analysis?.sharpness { x[soft.rawValue] = clamp(1 - log10(sharpness + 1) / 3) }
        x[screenshot.rawValue] = descriptor.isScreenshot ? 1 : 0
        x[similarExtra.rawValue] = isSimilarExtra ? 1 : 0
        x[burstExtra.rawValue] = isBurstExtra ? 1 : 0
        x[video.rawValue] = descriptor.mediaKind == .video ? 1 : 0
        x[longVideo.rawValue] = descriptor.mediaKind == .video ? clamp(descriptor.duration / 300) : 0
        if let created = descriptor.creationDate {
            let days = max(now.timeIntervalSince(created) / 86_400, 0)
            x[old.rawValue] = clamp(log10(days + 1) / 4)
        }
        let pixels = Double(max(descriptor.pixelWidth * descriptor.pixelHeight, 1))
        x[lowResolution.rawValue] = clamp(1 - log10(pixels) / 7.1)
        x[TasteFeature.subject.rawValue] = min(max(subject, -1), 1)
        x[TasteFeature.lookalike.rawValue] = min(max(lookalike, -1), 1)
        return x
    }
}

/// Logistic regression pulled toward the priors. With few labels it behaves like
/// the priors; with many it follows the user.
struct TasteModel: Sendable, Equatable {
    var weights: [Double]
    var bias: Double
    var trainedOn: Int

    static let prior = TasteModel(weights: TasteFeature.allCases.map(\.prior), bias: -3.0, trainedOn: 0)

    func probability(_ x: [Double]) -> Double {
        1 / (1 + exp(-logit(x)))
    }

    private func logit(_ x: [Double]) -> Double {
        zip(weights, x).reduce(bias) { $0 + $1.0 * $1.1 }
    }

    /// The feature that pushed hardest toward deletion, if any pushed at all.
    func strongestReason(_ x: [Double]) -> TasteFeature? {
        let contributions = zip(weights, x).map { $0 * $1 }
        guard let best = contributions.indices.max(by: { contributions[$0] < contributions[$1] }),
              contributions[best] > 0.05
        else { return nil }
        return TasteFeature(rawValue: best)
    }

    /// Gradient descent on log loss with an L2 pull toward the prior weights.
    /// `y` is 1 for "would delete", 0 for "keep".
    static func train(_ examples: [(x: [Double], y: Double)], epochs: Int = 400, rate: Double = 0.5,
                      pull: Double = 0.05) -> TasteModel {
        var model = prior
        guard !examples.isEmpty else { return model }
        let n = Double(examples.count)
        for _ in 0..<epochs {
            var gradW = [Double](repeating: 0, count: model.weights.count)
            var gradB = 0.0
            for example in examples {
                let error = model.probability(example.x) - example.y
                for i in gradW.indices { gradW[i] += error * example.x[i] }
                gradB += error
            }
            for i in model.weights.indices {
                let toward = model.weights[i] - prior.weights[i]
                model.weights[i] -= rate * (gradW[i] / n + pull * toward)
            }
            model.bias -= rate * (gradB / n + pull * (model.bias - prior.bias))
        }
        model.trainedOn = examples.count
        return model
    }
}
