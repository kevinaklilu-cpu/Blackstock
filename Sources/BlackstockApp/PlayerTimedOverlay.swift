#if os(macOS)
import AVFoundation
import SwiftUI

/// Keeps the playback clock and its view callback explicitly on MainActor.
/// Its task is cancelled when the overlay disappears or its player changes.
@MainActor
struct PlayerTimedOverlay<Content: View>: View {
    let player: AVPlayer
    @ViewBuilder let content: @MainActor (Double) -> Content
    @State private var seconds: Double = 0

    var body: some View {
        content(seconds)
            .task(id: ObjectIdentifier(player)) { @MainActor in
                while !Task.isCancelled {
                    let current = player.currentTime().seconds
                    let next = current.isFinite ? max(0, current) : 0
                    if seconds != next { seconds = next }
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return }
                }
            }
    }
}
#endif
