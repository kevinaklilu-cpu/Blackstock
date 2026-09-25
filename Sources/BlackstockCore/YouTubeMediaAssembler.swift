#if os(macOS)
import AVFoundation
import Foundation

/// Joins downloaded H.264 video and AAC audio using macOS, without a separate encoder.
public enum YouTubeMediaAssembler {
    public static func assemble(directory: URL, output: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        let videos = files.filter { $0.pathExtension.lowercased() == "mp4" }
        guard !videos.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for video in videos {
            let candidate = AVURLAsset(url: video)
            if !(try await candidate.loadTracks(withMediaType: .audio)).isEmpty,
               !(try await candidate.loadTracks(withMediaType: .video)).isEmpty {
                try? FileManager.default.removeItem(at: output)
                try FileManager.default.copyItem(at: video, to: output)
                return
            }
        }
        guard let video = videos.first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoAsset = AVURLAsset(url: video)
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
        // Some fragmented YouTube DASH files expose both audio and video at the
        // same incorrect multiple of their real duration. AVFoundation resolves
        // the AAC edit list during export, while the video media timeline keeps
        // the expanded duration. Verify a shared, known factor before applying
        // the video-only correction used below.
        guard let metadataURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any],
              let seconds = metadata["duration"] as? Double,
              seconds.isFinite, seconds > 0,
              videoDuration.seconds.isFinite, videoDuration.seconds > 0,
              audioDuration.seconds.isFinite, audioDuration.seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard abs(videoDuration.seconds - audioDuration.seconds) <= 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try destinationVideo.insertTimeRange(videoTimeRange, of: videoTrack, at: .zero)
        try destinationAudio.insertTimeRange(audioTimeRange, of: audioTrack, at: .zero)
        let needsTimelineNormalization =
            abs(videoDuration.seconds - seconds) > 1
            || abs(audioDuration.seconds - seconds) > 1
        if needsTimelineNormalization {
            let videoFactor = videoDuration.seconds / seconds
            let audioFactor = audioDuration.seconds / seconds
            let recognizedFactor = [0.5, 2.0].contains {
                abs(videoFactor - $0) <= 0.05
                    && abs(audioFactor - $0) <= 0.05
            }
            guard recognizedFactor,
                  abs(videoFactor - audioFactor) <= 0.02 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // The fragmented video track keeps the doubled media timeline after
            // export, while AAC resolves its edit list automatically. Correct
            // the video timeline only; scaling AAC would shorten it twice.
            destinationVideo.scaleTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                toDuration: CMTime(
                    seconds: seconds,
                    preferredTimescale: 600
                )
            )
        }
        destinationVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try Task.checkCancellation()
        let preset = needsTimelineNormalization
            ? AVAssetExportPresetHighestQuality
            : AVAssetExportPresetPassthrough
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
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
