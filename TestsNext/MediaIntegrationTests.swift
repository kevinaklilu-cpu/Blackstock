import Foundation
import AVFoundation
import CoreVideo
import Darwin

@available(macOS 13.0, *)
@main
struct MediaIntegrationTests {
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("blackstock-media-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("fixture.mov")
        try await makeFixture(at: source)
        let sourceInfo = try await MediaInspector.inspect(source)
        precondition(abs(sourceInfo.fps - 30) < 1.5)
        precondition(sourceInfo.width == 640 && sourceInfo.height == 360)

        let moment = ClipMoment(start: 0.4, end: 2.4, score: 90, title: "Fixture", rationale: ["test"], previewText: "test", source: "fixture")
        let original = base.appendingPathComponent("original.mov")
        try await HighQualityRenderService.export(sourceURL: source, moment: moment, aspect: .original, destination: original)
        let originalReport = await QualityGate.verify(source: sourceInfo, outputURL: original, requestedMoment: moment, aspect: .original)
        precondition(originalReport.passed, "Original export failed QA: \(originalReport.warnings)")

        let vertical = base.appendingPathComponent("vertical.mov")
        try await HighQualityRenderService.export(sourceURL: source, moment: moment, aspect: .vertical, destination: vertical)
        let verticalInfo = try await MediaInspector.inspect(vertical)
        precondition(verticalInfo.height > verticalInfo.width)
        precondition(verticalInfo.height <= sourceInfo.height + 2, "Vertical export upscaled source")
        let verticalReport = await QualityGate.verify(source: sourceInfo, outputURL: vertical, requestedMoment: moment, aspect: .vertical)
        precondition(verticalReport.passed, "Vertical export failed QA: \(verticalReport.warnings)")
        print("BLACKSTOCK_MARKET_READY_MEDIA_TESTS_OK")
    }

    private static func makeFixture(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 360
        ])
        guard writer.canAdd(input) else { throw BlackstockError.exportFailed("Fixture writer input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? BlackstockError.exportFailed("Fixture writer") }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw BlackstockError.exportFailed("Fixture pixel buffer pool") }
        for frame in 0..<90 {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess, let buffer = optionalBuffer else { throw BlackstockError.exportFailed("Fixture pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                memset(baseAddress, Int32((frame * 3) % 200 + 30), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) else { throw writer.error ?? BlackstockError.exportFailed("Fixture append") }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in writer.finishWriting { continuation.resume() } }
        guard writer.status == .completed else { throw writer.error ?? BlackstockError.exportFailed("Fixture finish") }
    }
}
