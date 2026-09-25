#if os(macOS)
import AVFoundation
import Foundation

/// Joins downloaded H.264 video and AAC audio using macOS, without a separate encoder.
public enum YouTubeMediaAssembler {
    public static func assemble(directory: URL, output: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        guard let video = files.first(where: { $0.pathExtension == "mp4" }),
              let audio = files.first(where: { $0.pathExtension == "m4a" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let destinationAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoDuration = try await videoTrack.load(.timeRange).duration
        let audioDuration = try await audioTrack.load(.timeRange).duration
        // Some YouTube 60-fps DASH MP4 headers are interpreted by AVFoundation
        // at half frame rate. Use the extractor's source duration to normalize
        // timestamps, rather than stretching the audio to an incorrect movie header.
        guard let metadataURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any],
              let seconds = metadata["duration"] as? Double,
              seconds.isFinite, seconds > 0,
              videoDuration.seconds.isFinite, videoDuration.seconds > 0,
              audioDuration.seconds.isFinite, audioDuration.seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        func normalizedDuration(_ duration: CMTime) throws -> CMTime {
            if abs(duration.seconds - seconds) <= 1 { return duration }
            for multiplier in [0.5, 2.0] {
                let corrected = CMTimeMultiplyByFloat64(duration, multiplier: multiplier)
                if abs(corrected.seconds - seconds) <= 1 { return corrected }
            }
            // Do not silently stretch unrelated or truncated tracks.
            throw CocoaError(.fileReadCorruptFile)
        }
        let normalizedVideoDuration = try normalizedDuration(videoDuration)
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        try destinationAudio.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: audioTrack, at: .zero)
        if abs(videoDuration.seconds - seconds) > 1 {
            destinationVideo.scaleTimeRange(CMTimeRange(start: .zero, duration: videoDuration), toDuration: normalizedVideoDuration)
        }
        // Keep AAC timestamps intact: AVFoundation resolves its fragmented
        // edit lists on export; applying the video-rate correction doubles speed.
        destinationVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try Task.checkCancellation()
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await AsyncAVAssetExporter.export(
            exporter,
            to: output,
            as: .mp4
        )
        let result = AVURLAsset(url: output)
        guard let resultVideo = try await result.loadTracks(withMediaType: .video).first,
              let resultAudio = try await result.loadTracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let resultVideoDuration = try await resultVideo.load(.timeRange).duration.seconds
        let resultAudioDuration = try await resultAudio.load(.timeRange).duration.seconds
        guard abs(resultVideoDuration - seconds) <= 1,
              abs(resultAudioDuration - seconds) <= 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
#endif
