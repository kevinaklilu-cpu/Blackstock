#if os(macOS)
import Darwin
import Dispatch
import Foundation

@MainActor
final class IngestDirectoryWatcher: ObservableObject {
    @Published private(set) var isWatching = false
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var errorMessage: String?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private let queue = DispatchQueue(
        label: "app.blackstock.ingest-watcher",
        qos: .utility
    )

    func start(
        directoryURL: URL,
        onChange: @escaping @Sendable () -> Void
    ) {
        stop()

        let descriptor = open(
            directoryURL.path,
            O_EVTONLY
        )
        guard descriptor >= 0 else {
            errorMessage =
                "Der Blackstock-Ingest-Ordner konnte nicht überwacht werden."
            return
        }

        fileDescriptor = descriptor
        let nextSource =
            DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [
                    .write,
                    .extend,
                    .attrib,
                    .rename,
                    .delete
                ],
                queue: queue
            )

        nextSource.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.lastEventAt = Date()
                self.errorMessage = nil
                onChange()
            }
        }

        nextSource.setCancelHandler {
            close(descriptor)
        }

        source = nextSource
        errorMessage = nil
        isWatching = true
        nextSource.resume()
    }

    func stop() {
        if let source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
        }

        fileDescriptor = -1
        isWatching = false
    }

    deinit {
        source?.cancel()
    }
}
#endif
