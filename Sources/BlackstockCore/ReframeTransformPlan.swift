#if os(macOS)
import Foundation
import CoreGraphics

public struct ReframeTransformPlan: Sendable, Equatable {
    public let renderWidth: Double
    public let renderHeight: Double
    public let crop: ReframeCropPlan
    public let transform: CGAffineTransform

    public init(
        renderWidth: Double,
        renderHeight: Double,
        crop: ReframeCropPlan,
        transform: CGAffineTransform
    ) {
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.crop = crop
        self.transform = transform
    }

    public static func make(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        spec: ReframeSpec,
        renderSize: CGSize
    ) -> ReframeTransformPlan? {
        guard naturalSize.width > 0,
              naturalSize.height > 0,
              renderSize.width > 0,
              renderSize.height > 0 else {
            return nil
        }

        let transformedBounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform)

        let orientedWidth = abs(transformedBounds.width)
        let orientedHeight = abs(transformedBounds.height)

        guard let crop = ReframeCropPlan.make(
            sourceWidth: orientedWidth,
            sourceHeight: orientedHeight,
            spec: spec
        ) else {
            return nil
        }

        let scaleX = renderSize.width / crop.cropWidth
        let scaleY = renderSize.height / crop.cropHeight

        var transform = preferredTransform
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -transformedBounds.minX,
                y: -transformedBounds.minY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -crop.cropX,
                y: -crop.cropY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        return .init(
            renderWidth: renderSize.width,
            renderHeight: renderSize.height,
            crop: crop,
            transform: transform
        )
    }
}

public extension LocalRenderPreset {
    func renderSize(
        for aspectRatio: ReframeAspectRatio
    ) -> CGSize {
        switch (self, aspectRatio) {
        case (.hd1080, .landscape16x9):
            return CGSize(width: 1920, height: 1080)
        case (.hd1080, .portrait9x16):
            return CGSize(width: 1080, height: 1920)
        case (.hd1080, .square1x1):
            return CGSize(width: 1080, height: 1080)
        case (.uhd4K, .landscape16x9):
            return CGSize(width: 3840, height: 2160)
        case (.uhd4K, .portrait9x16):
            return CGSize(width: 2160, height: 3840)
        case (.uhd4K, .square1x1):
            return CGSize(width: 2160, height: 2160)
        }
    }
}
#endif
