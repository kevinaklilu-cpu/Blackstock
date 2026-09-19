#if os(macOS)
import Foundation
import BlackstockCore

enum BlackstockInstalledSmokeTest {
    static let argument = "--blackstock-installed-smoke-test"

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(argument) else {
            return
        }

        do {
            try run()
            FileHandle.standardOutput.write(
                Data("BLACKSTOCK_SMOKE_PASS\n".utf8)
            )
            exit(EXIT_SUCCESS)
        } catch {
            FileHandle.standardError.write(
                Data("BLACKSTOCK_SMOKE_FAIL: \(error)\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        var graph = EditGraph(
            createdAt: Date(timeIntervalSince1970: 1)
        )
        _ = graph.apply(
            EditOperation(
                type: .removeRange,
                timeRange: .init(
                    startSeconds: 2,
                    durationSeconds: 3
                ),
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            actor: .user
        )

        let timeline = EditTimelineResolver().resolve(
            sourceDurationSeconds: 10,
            operations: graph.currentOperations
        )
        guard timeline.hasContent,
              abs(timeline.outputDurationSeconds - 7) < 0.001 else {
            throw SmokeFailure.timelineResolution
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("Blackstock", isDirectory: true)
            .appendingPathComponent(
                "SmokeTest-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let marker = directory.appendingPathComponent("marker.txt")
        let expected = "blackstock-installed-smoke"
        try expected.write(
            to: marker,
            atomically: true,
            encoding: .utf8
        )
        let actual = try String(
            contentsOf: marker,
            encoding: .utf8
        )
        guard actual == expected else {
            throw SmokeFailure.applicationSupportRoundTrip
        }
    }

    private enum SmokeFailure: Error {
        case timelineResolution
        case applicationSupportRoundTrip
    }
}
#endif
