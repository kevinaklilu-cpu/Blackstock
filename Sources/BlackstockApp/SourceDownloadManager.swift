#if os(macOS)
import Combine
import Foundation

enum SourceDownloadState: Equatable {
    case idle
    case downloading
    case paused
    case completed
    case failed(String)

    var germanTitle: String {
        switch self {
        case .idle: return "Bereit"
        case .downloading: return "Download läuft"
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

    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var pendingDestinationURL: URL?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    func start(
        remoteURL: URL,
        destinationURL: URL
    ) {
        cancel()
        self.destinationURL = destinationURL
        pendingDestinationURL = destinationURL
        lastCompletedURL = nil
        progress = 0
        bytesReceived = 0
        bytesExpected = 0
        state = .downloading

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
        guard state == .downloading,
              let task else {
            return
        }
        task.cancel(
            byProducingResumeData: { [weak self] data in
                DispatchQueue.main.async {
                guard let self else { return }
                self.resumeData = data
                self.task = nil
                    self.state = .paused
                }
            }
        )
    }

    func resume() {
        guard state == .paused,
              let resumeData else {
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
        task?.cancel()
        task = nil
        resumeData = nil
        pendingDestinationURL = nil
        progress = 0
        bytesReceived = 0
        bytesExpected = 0
        if state != .completed {
            state = .idle
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
            guard let self else { return }
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
            self.task = nil
            self.state = .failed(
                error.localizedDescription
            )
        }
    }
}
#endif
