import Foundation
import BlackstockCore

@main struct DownloadRecoverySmoke {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let helper = root.appendingPathComponent("yt-dlp")
        try """
        #!/usr/bin/python3
        import pathlib, sys, time
        pattern = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
        folder = pattern.parent
        partial = folder / '137.mp4.part'
        if partial.exists():
            assert partial.read_bytes() == b'partial-video-fixture'
            (folder / 'resumed').write_text('yes')
        else:
            partial.write_bytes(b'partial-video-fixture')
        print('BLACKSTOCK_PROGRESS: 25%', flush=True)
        time.sleep(60)
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        setenv("BLACKSTOCK_DOWNLOAD_TOOLS_DIR", root.path, 1)
        let destination = root.appendingPathComponent("project.mp4")
        let remote = URL(string: "https://www.youtube.com/watch?v=fixture")!
        var manager = SourceDownloadManager()
        func files(named name: String) -> [URL] {
            let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            return (iterator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == name }
        }
        manager.start(remoteURL: remote, destinationURL: destination)
        for _ in 0..<100 {
            if !files(named: "137.mp4.part").isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(files(named: "137.mp4.part").count == 1)
        manager.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)
        manager = SourceDownloadManager()
        manager.start(remoteURL: remote, destinationURL: destination)
        for _ in 0..<100 {
            if !files(named: "resumed").isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(files(named: "resumed").count == 1)
        precondition(manager.recoveredDownload)
        precondition(files(named: "137.mp4.part").count == 2)
        manager.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)
        manager = SourceDownloadManager()
        manager.start(remoteURL: URL(string: "https://www.youtube.com/watch?v=different")!, destinationURL: destination)
        for _ in 0..<100 {
            if files(named: "137.mp4.part").count == 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(files(named: "137.mp4.part").count == 3)
        precondition(!manager.recoveredDownload)
        precondition(files(named: "resumed").count == 1)
        manager.cancel()
        print("DOWNLOAD_RECOVERY_AND_SOURCE_ISOLATION_PASS")
    }
}
