#if os(macOS)
import SwiftUI
import AVKit

/// Use AVKit's native view directly. SwiftUI VideoPlayer crashes during generic
/// metadata initialization on some macOS 26 installations before playback begins.
struct BlackstockVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        view.setAccessibilityLabel("Video-Vorschau des aktuellen Schnitts")
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
#endif
