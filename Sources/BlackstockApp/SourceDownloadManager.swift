#if os(macOS)
import Combine
import CryptoKit
import Foundation
import BlackstockCore

enum SourceDownloadState: Equatable {
    case idle
    case downloading
    case processing
    case paused
    case completed
    case failed(String)

    var germanTitle: String {
        switch self {
        case .idle: return "Bereit"
        case .downloading: return "Download läuft"
        case .processing: return "Video wird vorbereitet"
        case .paused: return "Pausiert"
        case .completed: return "Download abgeschlossen"
        case .failed: return "Download fehlgeschlagen"
        }
    }
}

final class SourceDownloadManager:
    NSObject,
    ObservableObject,
    URLSessionDownloadDelegate {
    @Published private(set) var state:
        SourceDownloadState = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var bytesReceived: Int64 = 0
    @Published private(set) var bytesExpected: Int64 = 0
    @Published private(set) var destinationURL: URL?
    @Published private(set) var lastCompletedURL: URL?
    @Published private(set) var recoveredDownload = false

    private var assemblyTask: Task<Void, Never>?
    private var youtubeProcess: Process?
    private var youtubeGeneration = UUID()
    private var youtubeBuffer = ""
    private var youtubeDiagnostic = ""

    static var youtubeExecutable: URL? {
        let configured = ProcessInfo.processInfo.environment["BLACKSTOCK_DOWNLOAD_TOOLS_DIR"]
            .map { [$0 + "/yt-dlp"] } ?? []
        let paths = configured + [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/yt-dlp").path,
            "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/yt-dlp" }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var remoteURL: URL?
    private var pendingDestinationURL: URL?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: .main
        )
    }()

    func start(
        remoteURL: URL,
        destinationURL: URL
    ) {
        cancel()
        self.destinationURL = destinationURL
        self.remoteURL = remoteURL
        pendingDestinationURL = destinationURL
        lastCompletedURL = nil
        recoveredDownload = false
        progress = 0
        bytesReceived = 0
        bytesExpected = 0
        state = .downloading

        if YouTubeDownloadRequest.accepts(remoteURL) {
            startYouTube(remoteURL: remoteURL, destination: destinationURL)
            return
        }

        let request = URLRequest(
            url: remoteURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        let nextTask = session.downloadTask(
            with: request
        )
        task = nextTask
        nextTask.resume()
    }

    func pause() {
        if let process = youtubeProcess, state == .downloading {
            if process.suspend() { state = .paused }
            return
        }
        guard state == .downloading,
              let task else {
            return
        }
        task.cancel(
            byProducingResumeData: { [weak self] data in
                DispatchQueue.main.async {
                guard let self, self.task === task else { return }
                self.resumeData = data
                self.task = nil
                    self.state = .paused
                }
            }
        )
    }

    func resume() {
        if let process = youtubeProcess, state == .paused {
            if process.resume() { state = .downloading }
            return
        }
        guard state == .paused else { return }
        guard let resumeData else {
            if let remoteURL, let destinationURL {
                start(remoteURL: remoteURL, destinationURL: destinationURL)
            }
            return
        }
        state = .downloading
        let nextTask = session.downloadTask(
            withResumeData: resumeData
        )
        self.resumeData = nil
        task = nextTask
        nextTask.resume()
    }

    func cancel() {
        youtubeGeneration = UUID()
        assemblyTask?.cancel()
        assemblyTask = nil
        if let process = youtubeProcess, process.isRunning {
            if state == .paused { _ = process.resume() }
            process.terminate()
        }
        youtubeProcess = nil
        task?.cancel()
        task = nil
        resumeData = nil
        remoteURL = nil
        pendingDestinationURL = nil
        progress = 0
        bytesReceived = 0
        bytesExpected = 0
        state = .idle
    }

    private func startYouTube(remoteURL: URL, destination: URL) {
        guard let executable = Self.youtubeExecutable else {
            state = .failed("Die Download-Komponente fehlt. Installiere yt-dlp oder verwende ein Blackstock-Paket mit integrierter Download-Komponente.")
            return
        }
        let generation = UUID()
        youtubeGeneration = generation
        youtubeBuffer = ""
        youtubeDiagnostic = ""
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        // Download outside the watched ingest folder until the file is complete.
        let identity = destination.standardizedFileURL.path + "\n" + remoteURL.absoluteString
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let recoveryRoot = destination.deletingLastPathComponent()
            .appendingPathComponent(".downloads", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        let staging = recoveryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            let manager = FileManager.default
            let previous = (try? manager.contentsOfDirectory(
                at: recoveryRoot, includingPropertiesForKeys: [.creationDateKey]
            ))?.sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }.first
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            // A fresh attempt snapshots partial tracks. An orphaned downloader from
            // a crashed app cannot write into this attempt's files.
            if let previous {
                for file in try manager.contentsOfDirectory(at: previous, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          file.lastPathComponent != "video.mp4" else { continue }
                    try manager.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
                    recoveredDownload = true
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            state = .failed(error.localizedDescription)
            return
        }
        let output = staging.appendingPathComponent("video.mp4")
        process.arguments = YouTubeDownloadRequest.arguments(
            url: remoteURL, output: staging.appendingPathComponent("%(format_id)s.%(ext)s")
        )
        let bundledDeno = executable.deletingLastPathComponent().appendingPathComponent("deno")
        if FileManager.default.isExecutableFile(atPath: bundledDeno.path) {
            process.arguments?.insert(contentsOf: ["--js-runtimes", "deno:" + bundledDeno.path], at: 0)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path
            + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                guard let self, self.youtubeGeneration == generation else { return }
                self.youtubeBuffer += chunk
                while let range = self.youtubeBuffer.range(of: "\n") {
                    let line = String(self.youtubeBuffer[..<range.lowerBound])
                    self.youtubeBuffer.removeSubrange(...range.lowerBound)
                    if let value = YouTubeDownloadRequest.progress(line) {
                        self.progress = value
                    } else if !line.isEmpty {
                        self.youtubeDiagnostic = String(line.suffix(1200))
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.youtubeGeneration == generation else {
                    return
                }
                self.youtubeProcess = nil
                guard finished.terminationStatus == 0 else {
                    self.state = .failed("YouTube-Download fehlgeschlagen. " + self.youtubeDiagnostic)
                    return
                }
                self.state = .processing
                self.assemblyTask = Task { @MainActor in
                    do {
                        try await YouTubeMediaAssembler.assemble(directory: staging, output: output)
                        try Task.checkCancellation()
                        guard self.youtubeGeneration == generation else { return }
                        try FileManager.default.moveItem(at: output, to: destination)
                        try? FileManager.default.removeItem(at: recoveryRoot)
                        self.progress = 1
                        self.pendingDestinationURL = nil
                        self.state = .completed
                        self.lastCompletedURL = destination
                    } catch {
                        guard self.youtubeGeneration == generation else { return }
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
        }
        youtubeProcess = process
        do { try process.run() }
        catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            youtubeProcess = nil
            try? FileManager.default.removeItem(at: staging)
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        cancel()
        destinationURL = nil
        lastCompletedURL = nil
        state = .idle
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite:
            Int64
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.task === downloadTask else { return }
            self.bytesReceived =
                totalBytesWritten
            self.bytesExpected =
                max(totalBytesExpectedToWrite, 0)
            if totalBytesExpectedToWrite > 0 {
                self.progress = min(
                    max(
                        Double(totalBytesWritten)
                        / Double(
                            totalBytesExpectedToWrite
                        ),
                        0
                    ),
                    1
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard self.task === downloadTask else { return }
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              !(response.mimeType?.lowercased().contains("text/html") ?? false) else {
            self.task = nil
            state = .failed("Die Quelle hat keine Videodatei geliefert. Prüfe den Link und versuche es erneut.")
            return
        }
        guard let destination =
                pendingDestinationURL else {
            DispatchQueue.main.async {
                self.state = .failed(
                    "Kein Download-Ziel vorhanden."
                )
            }
            return
        }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination
                    .deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(
                atPath: destination.path
            ) {
                try fileManager.removeItem(
                    at: destination
                )
            }
            try fileManager.moveItem(
                at: location,
                to: destination
            )

            DispatchQueue.main.async {
                guard self.task === downloadTask else { return }
                self.progress = 1
                self.lastCompletedURL =
                    destination
                self.destinationURL =
                    destination
                self.pendingDestinationURL =
                    nil
                self.task = nil
                self.state = .completed
            }
        } catch {
            DispatchQueue.main.async {
                guard self.task === downloadTask else { return }
                self.state = .failed(
                    error.localizedDescription
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            return
        }

        DispatchQueue.main.async {
            guard self.task === task else { return }
            self.task = nil
            self.state = .failed(
                error.localizedDescription
            )
        }
    }
}
#endif
