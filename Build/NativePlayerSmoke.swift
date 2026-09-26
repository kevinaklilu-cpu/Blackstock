import AppKit
import SwiftUI
import AVKit

@main
struct NativePlayerSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let player = AVPlayer(url: url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        Task { @MainActor in
            do {
                _ = try await AVURLAsset(url: url).load(.duration)
                for index in 0..<5 {
                    window.contentView = NSHostingView(rootView: BlackstockVideoPlayer(player: player))
                    window.makeKeyAndOrderFront(nil)
                    await player.seek(to: CMTime(seconds: Double(index * 10), preferredTimescale: 600))
                    player.play()
                    try await Task.sleep(for: .seconds(1))
                    guard player.currentItem?.status == .readyToPlay else {
                        fatalError("Player did not become ready")
                    }
                    player.pause()
                    window.contentView = nil
                }
                window.close()
                print("NATIVE_PLAYER_PASS: five mount/play/seek/unmount cycles")
                app.terminate(nil)
            } catch { fatalError("Player failed: \(error)") }
        }
        app.run()
    }
}
