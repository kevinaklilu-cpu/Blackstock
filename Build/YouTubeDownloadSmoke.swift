import Foundation
import AVFoundation
import BlackstockCore

@main struct Smoke {
    @MainActor static func main() async throws {
        precondition(YouTubeDownloadRequest.accepts(URL(string: "https://youtu.be/abc")!))
        precondition(!YouTubeDownloadRequest.accepts(URL(string: "https://youtube.com.evil.test")!))
        precondition(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: 42.5%") == 0.425)
        precondition(YouTubeDownloadRequest.progress("BLACKSTOCK_PROGRESS: nan%") == nil)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        var manager = SourceDownloadManager()
        let watcher = IngestDirectoryWatcher()
        var ingestEvents = 0
        watcher.start(directoryURL: destination.deletingLastPathComponent()) { ingestEvents += 1 }
        defer { watcher.stop() }
        let canceledDestination = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        manager.start(remoteURL: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, destinationURL: canceledDestination)
        manager.cancel()
        precondition(manager.state == .idle)
        precondition(!FileManager.default.fileExists(atPath: canceledDestination.path))
        print("CANCEL_RESTART_PASS")
        manager.start(remoteURL: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, destinationURL: destination)
        var paused = false
        var recovered = false
        for tick in 0..<600 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if tick == 7, manager.state == .downloading {
                manager.pause()
                precondition(manager.state == .paused)
                try await Task.sleep(nanoseconds: 2_000_000_000)
                manager.resume()
                precondition(manager.state == .downloading)
                paused = true
                print("PAUSE_RESUME_PASS")
            }
            if paused, !recovered, manager.state == .downloading, manager.progress > 0.1 {
                manager.cancel()
                // Recreate the manager: no in-memory task or resume data survives.
                try await Task.sleep(nanoseconds: 1_000_000_000)
                manager = SourceDownloadManager()
                manager.start(remoteURL: URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ")!, destinationURL: destination)
                recovered = true
                print("NEW_MANAGER_RECOVERY_STARTED")
            }
            if tick % 10 == 0 { print("STATE", manager.state, manager.progress) }
            if case .failed(let message) = manager.state { fatalError(message) }
            if manager.state == .completed {
                let asset = AVURLAsset(url: destination)
                let video = try await asset.loadTracks(withMediaType: .video)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                let duration = try await asset.load(.duration).seconds
                precondition(!video.isEmpty && !audio.isEmpty && duration > 630 && duration < 640)
                let videoRange = try await video[0].load(.timeRange)
                let audioRange = try await audio[0].load(.timeRange)
                precondition(abs(videoRange.duration.seconds - audioRange.duration.seconds) < 1)
                let generator = AVAssetImageGenerator(asset: asset)
                for second in [30.0, 300.0, 600.0] {
                    let frame = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600))
                    precondition(frame.image.width > 0)
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                    reader.add(output)
                    reader.timeRange = CMTimeRange(start: CMTime(seconds: second, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
                    precondition(reader.startReading())
                    precondition(output.copyNextSampleBuffer() != nil)
                    reader.cancelReading()
                    print("DECODE_PASS", second)
                }
                precondition(ingestEvents > 0)
                precondition(recovered)
                print("NEW_MANAGER_RECOVERY_PASS")
                print("INGEST_WATCHER_PASS", ingestEvents)
                print("DOWNLOAD_MUX_PASS", duration, destination.path, "pause tested:", paused)
                return
            }
        }
        manager.cancel()
        fatalError("Download timed out")
    }
}
