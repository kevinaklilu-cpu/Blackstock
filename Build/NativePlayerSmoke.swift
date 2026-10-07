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
                for index in 0..<20 {
                    window.contentView = NSHostingView(rootView: BlackstockVideoPlayer(player: player)
                        .overlay {
                            PlayerTimedOverlay(player: player) { seconds in
                                Text("Overlay " + String(format: "%.1f", seconds))
                            }
                        }
                        .overlay(alignment: .bottom) {
                            PlayerTimedOverlay(player: player) { seconds in
                                if seconds.truncatingRemainder(dividingBy: 2) < 1 {
                                    Text("Untertitel-Test")
                                }
                            }
                        })
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
                print("NATIVE_PLAYER_PASS: twenty mount/play/seek/unmount cycles with timed text and caption overlays")
                app.terminate(nil)
            } catch { fatalError("Player failed: \(error)") }
        }
        app.run()
    }
}
