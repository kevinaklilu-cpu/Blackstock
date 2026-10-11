#if os(macOS)
import Darwin
import Combine
import Dispatch
import Foundation

@MainActor
final class IngestDirectoryWatcher: ObservableObject {
    @Published private(set) var isWatching = false
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var errorMessage: String?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    // Dispatch handlers created here inherit MainActor isolation. Dispatching
    // them on a utility queue traps before a nested Task can hop to MainActor.
    private let queue = DispatchQueue.main
    private var generation = UUID()

    func start(
        directoryURL: URL,
        onChange: @escaping @MainActor @Sendable () -> Void
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
        let currentGeneration = generation
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
            guard let self, self.generation == currentGeneration else { return }
            self.lastEventAt = Date()
            self.errorMessage = nil
            onChange()
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
        generation = UUID()
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
