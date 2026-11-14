import CoreGraphics
import Foundation
import Vision

/// Runs the on-device checks for one photo: aesthetics, utility, feature print, sharpness.
struct VisionAnalyzer: Sendable {
    static let sharpnessSide = 512

    struct Output: Sendable {
        var analysis: AssetAnalysis
        var print: FeaturePrintObservation?
        var tags: SubjectTags = [:]
    }

    /// Keep the classifier's strongest answers; the long tail is noise.
    static let tagFloor: Float = 0.1
    static let maxTags = 12

    func analyze(_ image: CGImage) async -> Output {
        let aesthetics = try? await CalculateImageAestheticsScoresRequest().perform(on: image)
        let traits = await self.traits(image)
        return Output(
            analysis: AssetAnalysis(
                aestheticScore: aesthetics?.overallScore,
                isUtility: aesthetics?.isUtility ?? false,
                sharpness: Self.sharpness(of: image)
            ),
            print: traits.print,
            tags: traits.tags
        )
    }

    /// What learning needs from a decided photo: what it shows and how it looks.
    func traits(_ image: CGImage) async -> (tags: SubjectTags, print: FeaturePrintObservation?) {
        let print = try? await GenerateImageFeaturePrintRequest().perform(on: image)
        let observations = (try? await ClassifyImageRequest().perform(on: image)) ?? []
        let top = observations
            .filter { $0.confidence >= Self.tagFloor }
            .sorted { $0.confidence > $1.confidence }
            .prefix(Self.maxTags)
        return (Dictionary(top.map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max), print)
    }

    /// Laplacian variance after scaling the long side to `sharpnessSide`, so scores
    /// compare across photo sizes.
    static func sharpness(of image: CGImage) -> Double? {
        let longSide = max(image.width, image.height)
        guard longSide > 0 else { return nil }
        let scale = min(1, Double(sharpnessSide) / Double(longSide))
        let width = max(3, Int(Double(image.width) * scale))
        let height = max(3, Int(Double(image.height) * scale))
        var gray = [UInt8](repeating: 0, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return BlurScorer.laplacianVariance(gray: gray, width: width, height: height)
    }
}
