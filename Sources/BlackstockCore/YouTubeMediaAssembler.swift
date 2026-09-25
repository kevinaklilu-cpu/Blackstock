#if os(macOS)
import AVFoundation
import Foundation

/// Joins downloaded H.264 video and AAC audio using macOS, without a separate encoder.
public enum YouTubeMediaAssembler {
    public static func assemble(directory: URL, output: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        guard let video = files.first(where: { $0.pathExtension == "mp4" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoAsset = AVURLAsset(url: video)
        let embeddedAudio = try await videoAsset.loadTracks(withMediaType: .audio)
        if !embeddedAudio.isEmpty {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: video, to: output)
            return
        }
        guard let audio = files.first(where: { $0.pathExtension == "m4a" }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let composition = AVMutableComposition()
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let destinationAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        let videoDuration = videoTimeRange.duration
        let audioDuration = audioTimeRange.duration
        // Never repair a malformed DASH header by stretching either track. That
        // changes playback speed and causes visible lip sync errors. A combined
        // A/V MP4 is preferred; this fallback accepts separate tracks only when
        // both source timelines already agree with the extractor metadata.
        guard let metadataURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any],
              let seconds = metadata["duration"] as? Double,
              seconds.isFinite, seconds > 0,
              videoDuration.seconds.isFinite, videoDuration.seconds > 0,
              audioDuration.seconds.isFinite, audioDuration.seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard abs(videoDuration.seconds - seconds) <= 1,
              abs(audioDuration.seconds - seconds) <= 1,
              abs(videoDuration.seconds - audioDuration.seconds) <= 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try destinationVideo.insertTimeRange(videoTimeRange, of: videoTrack, at: .zero)
        try destinationAudio.insertTimeRange(audioTimeRange, of: audioTrack, at: .zero)
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
