#if os(macOS)
import SwiftUI
import AVKit
import BlackstockCore

struct StorySceneCard: View {
    let title: String
    let role: String
    let fileURL: URL
    let sourceStart: Double
    let duration: Double
    let outputStart: Double
    let placements: [SupplementalVideoInsertInput]
    let sceneExplanations: [String]
    let explanation: String
    let canPreviewResult: Bool
    let pauseMainPlayer: () -> Void
    let previewResult: (Double) -> Void
    @State private var thumbnail: NSImage?
    @State private var previewPlayer: AVPlayer?
    @State private var showPreview = false
    @State private var selectedScene: SupplementalVideoInsertInput?
    private var previewStart: Double { selectedScene?.sourceStartSeconds ?? sourceStart }
    private var previewDuration: Double { selectedScene?.durationSeconds ?? duration }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { selectedScene = nil; pauseMainPlayer(); showPreview = true } label: {
                ZStack {
                    Color.black
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(.white)
                        .shadow(radius: 5)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quellenausschnitt abspielen: " + title)
            HStack {
                Text(role.uppercased()).font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(BlackstockDesign.accent)
                Spacer()
                Text(time(duration)).font(.caption.monospacedDigit())
            }
            Text(title).font(.callout.weight(.semibold)).lineLimit(2)
            HStack {
                Label("Quelle " + time(sourceStart) + "–" + time(sourceStart + duration), systemImage: "film")
                Spacer(minLength: 0)
            }.font(.caption2).foregroundStyle(.secondary)
            Button { previewResult(placements.first?.timelineStartSeconds ?? outputStart) } label: {
                Label("\(placements.count) Szenen · Ergebnis ansehen", systemImage: "play.rectangle")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!canPreviewResult)
            .help(canPreviewResult ? "Gemeinsamen Export an dieser Stelle ansehen" : "Nach dem Rendern verfügbar")
            DisclosureGroup("Szenen im Schnitt") {
                ForEach(Array(placements.enumerated()), id: \.offset) { index, scene in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). Quelle " + time(scene.sourceStartSeconds) + "–" + time(scene.sourceStartSeconds + scene.durationSeconds))
                            .font(.caption2.monospacedDigit())
                        HStack {
                            Button {
                                selectedScene = scene
                                pauseMainPlayer()
                                showPreview = true
                            } label: { Label("Quelle abspielen", systemImage: "play.circle") }
                            Button { previewResult(scene.timelineStartSeconds) } label: {
                                Text("Im Ergebnis · " + time(scene.timelineStartSeconds))
                            }.disabled(!canPreviewResult)
                        }.font(.caption2)
                        if sceneExplanations.indices.contains(index) {
                            Text(sceneExplanations[index]).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 4)
                }
            }.font(.caption)
            DisclosureGroup("Warum dieser Ausschnitt?") {
                Text(explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }.font(.caption)
        }
        .padding(12)
        .background(BlackstockDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BlackstockDesign.subtleBorder))
        .task(id: fileURL.path + String(sourceStart) + String(duration)) {
            thumbnail = nil
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            defer { generator.cancelAllCGImageGeneration() }
            if let image = try? await generator.image(at: CMTime(seconds: sourceStart + min(duration * 0.5, 2), preferredTimescale: 600)).image,
               !Task.isCancelled {
                thumbnail = NSImage(cgImage: image, size: .zero)
            }
        }
        .sheet(isPresented: $showPreview) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(title).font(.headline).lineLimit(2)
                        Text("Quellenausschnitt · Originalton").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Schließen") { showPreview = false }
                }
                VideoPlayer(player: previewPlayer).frame(height: 360)
                Text("Quelle " + time(previewStart) + "–" + time(previewStart + previewDuration))
                    .font(.caption.monospacedDigit())
            }
            .padding(20).frame(width: 680)
            .task {
                let item = AVPlayerItem(url: fileURL)
                item.forwardPlaybackEndTime = CMTime(seconds: previewStart + previewDuration, preferredTimescale: 600)
                let player = AVPlayer(playerItem: item)
                previewPlayer = player
                await player.seek(to: CMTime(seconds: previewStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                if !Task.isCancelled { player.play() }
            }
            .onDisappear { previewPlayer?.pause(); previewPlayer?.replaceCurrentItem(with: nil); previewPlayer = nil }
        }
    }
}
#endif
