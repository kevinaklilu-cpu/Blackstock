#if os(macOS)
import AVFoundation
import Foundation

public enum YouTubeMediaAssembler {
    /// Decode fragmented streams once. Never scale a composition from guessed
    /// edit-list factors: AVFoundation can resolve those factors again on export.
    public static func assemble(directory: URL, output: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let metadataURL = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
              let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any],
              let expected = (metadata["duration"] as? NSNumber)?.doubleValue,
              expected.isFinite, expected > 0 else { throw CocoaError(.fileReadCorruptFile) }
        var videoTrack: AVAssetTrack?
        var audioTrack: AVAssetTrack?
        var videoAsset: AVURLAsset?
        var audioAsset: AVURLAsset?
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ["mp4", "m4a"].contains(file.pathExtension.lowercased()) && file != output {
            let asset = AVURLAsset(url: file)
            if videoTrack == nil, let track = try await asset.loadTracks(withMediaType: .video).first {
                videoTrack = track; videoAsset = asset
            }
            if audioTrack == nil, let track = try await asset.loadTracks(withMediaType: .audio).first {
                audioTrack = track; audioAsset = asset
            }
        }
        guard let videoTrack, let audioTrack else { throw CocoaError(.fileReadCorruptFile) }
        let fps = Double(try await videoTrack.load(.nominalFrameRate))
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let descriptions = try await audioTrack.load(.formatDescriptions)
        guard let description = descriptions.first,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              fps.isFinite, fps > 0, fps <= 60,
              format.pointee.mSampleRate > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let rate = format.pointee.mSampleRate
        let channels = Int(format.pointee.mChannelsPerFrame)
        guard let videoAsset, let audioAsset else { throw CocoaError(.fileReadCorruptFile) }
        let videoReader = try AVAssetReader(asset: videoAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoOutput.alwaysCopiesSampleData = false
        videoReader.add(videoOutput)
        let audioReader = try AVAssetReader(asset: audioAsset)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        audioReader.add(audioOutput)
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(4_000_000, Int(size.width * size.height * 5)), AVVideoExpectedSourceFrameRateKey: fps]
        ])
        videoInput.transform = transform
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 192_000
        ])
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(videoInput); writer.add(audioInput)
        guard writer.startWriting(), videoReader.startReading(), audioReader.startReading() else {
            throw writer.error ?? videoReader.error ?? audioReader.error ?? CocoaError(.fileReadCorruptFile)
        }
        writer.startSession(atSourceTime: .zero)
        do {
            var videoFrames: Int64 = 0
            var audioFrames: Int64 = 0
            var videoDone = false
            var audioDone = false
            while !videoDone || !audioDone {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                var progressed = false
                if !videoDone && videoInput.isReadyForMoreMediaData {
                    if let sample = videoOutput.copyNextSampleBuffer() {
                        guard let pixel = CMSampleBufferGetImageBuffer(sample),
                              adapter.append(pixel, withPresentationTime: CMTime(seconds: Double(videoFrames) / fps, preferredTimescale: 60_000)) else {
                            throw writer.error ?? CocoaError(.fileReadCorruptFile)
                        }
                        videoFrames += 1
                    } else {
                        guard videoReader.status == .completed else { throw videoReader.error ?? CocoaError(.fileReadCorruptFile) }
                        videoInput.markAsFinished()
                        videoDone = true
                    }
                    progressed = true
                }
                if !audioDone && audioInput.isReadyForMoreMediaData {
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)),
                            presentationTimeStamp: CMTime(value: audioFrames, timescale: CMTimeScale(rate)), decodeTimeStamp: .invalid)
                        var timed: CMSampleBuffer?
                        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                            sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                            sampleBufferOut: &timed) == noErr, let timed, audioInput.append(timed) else {
                            throw writer.error ?? CocoaError(.fileReadCorruptFile)
                        }
                        audioFrames += Int64(CMSampleBufferGetNumSamples(sample))
                    } else {
                        guard audioReader.status == .completed else { throw audioReader.error ?? CocoaError(.fileReadCorruptFile) }
                        audioInput.markAsFinished()
                        audioDone = true
                    }
                    progressed = true
                }
                if !progressed { try await Task.sleep(for: .milliseconds(2)) }
            }
            let durations = [Double(videoFrames) / fps, Double(audioFrames) / rate]
            // Reject missing frames, VFR that cannot safely use this cadence,
            // and truncated audio rather than stretching either stream to fit.
            guard durations.count == 2, durations.allSatisfy({ abs($0 - expected) <= 1 }),
                  abs(durations[0] - durations[1]) <= 0.75 else { throw CocoaError(.fileReadCorruptFile) }
            // Give both tracks the same explicit end boundary. AAC packet padding
            // must not extend the editable movie beyond its actual picture.
            writer.endSession(atSourceTime: CMTime(seconds: min(durations[0], durations[1]), preferredTimescale: 60_000))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        } catch {
            videoReader.cancelReading(); audioReader.cancelReading(); writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
#endif
