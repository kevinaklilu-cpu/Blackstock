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
                // Progressive YouTube files can carry fragmented timestamps or
                // edit lists that AVPlayer interprets differently for audio and
                // video. Copying those bytes unchanged caused fast video and a
                // delayed soundtrack in the editor. Rebuild one shared zero-
                // based timeline even when yt-dlp already delivered both tracks.
                try await normalizeCombinedDownload(
                    asset: candidate,
                    files: files,
                    output: output
                )
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

    private static func normalizeCombinedDownload(
        asset: AVURLAsset,
        files: [URL],
        output: URL
    ) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = try await asset
                .loadTracks(withMediaType: .video).first,
              let audioTrack = try await asset
                .loadTracks(withMediaType: .audio).first,
              let destinationVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ),
              let destinationAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoRange = try await videoTrack.load(.timeRange)
        let audioRange = try await audioTrack.load(.timeRange)
        try destinationVideo.insertTimeRange(
            videoRange,
            of: videoTrack,
            at: .zero
        )
        try destinationAudio.insertTimeRange(
            audioRange,
            of: audioTrack,
            at: .zero
        )
        destinationVideo.preferredTransform = try await videoTrack
            .load(.preferredTransform)

        let metadataDuration = try downloadedDuration(from: files)
        let videoFactor = videoRange.duration.seconds / metadataDuration
        let audioFactor = audioRange.duration.seconds / metadataDuration
        let recognized: (Double) -> Bool = { factor in
            [0.5, 1.0, 2.0].contains { abs(factor - $0) <= 0.05 }
        }
        guard recognized(videoFactor), recognized(audioFactor) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if abs(videoFactor - 1) > 0.05 {
            destinationVideo.scaleTimeRange(
                CMTimeRange(start: .zero, duration: videoRange.duration),
                toDuration: CMTime(
                    seconds: metadataDuration,
                    preferredTimescale: 600
                )
            )
        }
        // When both fragmented tracks expose the same expanded edit-list
        // duration, AVFoundation resolves AAC during export. Scale audio only
        // when its factor differs from the video's factor.
        if abs(audioFactor - 1) > 0.05,
           abs(audioFactor - videoFactor) > 0.02 {
            destinationAudio.scaleTimeRange(
                CMTimeRange(start: .zero, duration: audioRange.duration),
                toDuration: CMTime(
                    seconds: metadataDuration,
                    preferredTimescale: 600
                )
            )
        }

        try? FileManager.default.removeItem(at: output)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await AsyncAVAssetExporter.export(
            exporter,
            to: output,
            as: .mp4
        )
        try await validateSynchronizedOutput(
            output,
            expectedDuration: metadataDuration
        )
    }

    private static func downloadedDuration(
        from files: [URL]
    ) throws -> Double {
        guard let metadataURL = files.first(
            where: { $0.lastPathComponent.hasSuffix(".info.json") }
        ),
        let metadata = try JSONSerialization.jsonObject(
            with: Data(contentsOf: metadataURL)
        ) as? [String: Any],
        let seconds = (metadata["duration"] as? NSNumber)?.doubleValue,
        seconds.isFinite,
        seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return seconds
    }

    private static func validateSynchronizedOutput(
        _ output: URL,
        expectedDuration: Double
    ) async throws {
        let result = AVURLAsset(url: output)
        guard let video = try await result
                .loadTracks(withMediaType: .video).first,
              let audio = try await result
                .loadTracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let videoRange = try await video.load(.timeRange)
        let audioRange = try await audio.load(.timeRange)
        guard abs(videoRange.start.seconds) <= 0.1,
              abs(audioRange.start.seconds) <= 0.1,
              abs(videoRange.duration.seconds - expectedDuration) <= 1,
              abs(audioRange.duration.seconds - expectedDuration) <= 1,
              abs(
                videoRange.duration.seconds
                    - audioRange.duration.seconds
              ) <= 0.75 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
#endif
