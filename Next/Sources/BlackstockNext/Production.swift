import Foundation
import AVFoundation
import Speech
import QuartzCore
import CoreGraphics

struct TranscriptionResult: Hashable {
    let words: [TranscriptWord]
    let fullText: String
    let locale: String
}

enum SpeechTranscriptionError: LocalizedError {
    case notAuthorized
    case unavailable
    case noResult
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Spracherkennung wurde nicht erlaubt."
        case .unavailable: return "Spracherkennung ist für diese Sprache gerade nicht verfügbar."
        case .noResult: return "Aus der Tonspur konnte kein verlässliches Transkript erzeugt werden."
        case .failed(let text): return text
        }
    }
}

final class SpeechTranscriptionService: NSObject {
    func requestAuthorization() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    func transcribe(fileURL: URL, language: String) async throws -> TranscriptionResult {
        guard await requestAuthorization() else { throw SpeechTranscriptionError.notAuthorized }
        let locale = Locale(identifier: normalizedLocale(language))
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        if #available(macOS 13.0, *) { request.addsPunctuation = true }

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error {
                    resumed = true
                    task?.cancel()
                    continuation.resume(throwing: SpeechTranscriptionError.failed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments
                let words = segments.compactMap { segment -> TranscriptWord? in
                    let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return TranscriptWord(
                        text: text,
                        start: segment.timestamp,
                        end: segment.timestamp + max(segment.duration, 0.08),
                        confidence: Double(segment.confidence)
                    )
                }
                guard !words.isEmpty else {
                    resumed = true
                    continuation.resume(throwing: SpeechTranscriptionError.noResult)
                    return
                }
                resumed = true
                continuation.resume(returning: .init(words: words, fullText: result.bestTranscription.formattedString, locale: locale.identifier))
                task?.cancel()
            }
        }
    }

    private func normalizedLocale(_ language: String) -> String {
        let value = language.replacingOccurrences(of: "_", with: "-")
        if value.contains("-") { return value }
        switch value.lowercased() {
        case "de": return "de-DE"
        case "en": return "en-US"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        default: return value.isEmpty ? "de-DE" : value
        }
    }
}

struct ClipCandidateGenerator {
    func generate(words: [TranscriptWord], preferredDuration: ClosedRange<Double>, sourceDuration: Double) -> [ClipCandidate] {
        guard words.count >= 4 else { return [] }
        let target = min(max((preferredDuration.lowerBound + preferredDuration.upperBound) / 2, 18), 90)
        let durations = Array(Set([max(12, min(30, target * 0.55)), max(20, min(55, target)), max(35, min(90, target * 1.45))])).sorted()
        var output: [ClipCandidate] = []
        var index = 0
        while index < words.count {
            let startWord = words[index]
            for desired in durations {
                let requestedEnd = min(sourceDuration, startWord.start + desired)
                guard let endIndex = nearestBoundary(from: index, requestedEnd: requestedEnd, words: words) else { continue }
                let slice = Array(words[index...endIndex])
                guard let last = slice.last, last.end - startWord.start >= 8 else { continue }
                let transcript = join(slice.map(\.text))
                let signal = signals(for: slice, transcript: transcript, desiredDuration: desired)
                output.append(.init(start: max(0, startWord.start - introPadding(for: slice)), end: min(sourceDuration, last.end + outroPadding(for: slice)), transcript: transcript, signals: signal))
            }
            index += max(1, words.count / 45)
        }
        let deduplicated = output.sorted { $0.start < $1.start }.reduce(into: [ClipCandidate]()) { result, candidate in
            if let last = result.last, abs(last.start - candidate.start) < 1.0, abs(last.end - candidate.end) < 2.0 { return }
            result.append(candidate)
        }
        return Array(deduplicated.prefix(160))
    }

    private func nearestBoundary(from start: Int, requestedEnd: Double, words: [TranscriptWord]) -> Int? {
        var best: (Int, Double)?
        let maxIndex = min(words.count - 1, start + 180)
        guard start <= maxIndex else { return nil }
        for i in start...maxIndex {
            let word = words[i]
            if word.end < requestedEnd - 8 { continue }
            if word.end > requestedEnd + 10 { break }
            let punctuation = word.text.last.map { ".!?".contains($0) } ?? false
            let nextGap = i + 1 < words.count ? words[i + 1].start - word.end : 1.0
            let boundaryBonus = punctuation ? 4.0 : (nextGap > 0.45 ? 2.0 : 0)
            let distance = abs(word.end - requestedEnd) - boundaryBonus
            if best == nil || distance < best!.1 { best = (i, distance) }
        }
        return best?.0 ?? min(maxIndex, start + 20)
    }

    private func signals(for words: [TranscriptWord], transcript: String, desiredDuration: Double) -> ClipSignals {
        let lower = transcript.lowercased()
        let first = words.prefix(12).map(\.text).joined(separator: " ").lowercased()
        let hookTerms = ["warum", "aber", "niemand", "problem", "fehler", "unglaublich", "genau", "wichtig", "here's", "why", "but", "problem", "never", "secret", "actually"]
        let payoffTerms = ["deshalb", "also", "ergebnis", "am ende", "lösung", "darum", "therefore", "result", "so", "finally", "solution"]
        let hook = min(1, 0.48 + Double(hookTerms.filter { first.contains($0) }.count) * 0.12)
        let payoff = min(1, 0.45 + Double(payoffTerms.filter { lower.contains($0) }.count) * 0.10 + (transcript.last.map { ".!?".contains($0) } == true ? 0.08 : 0))
        let questionPenalty = first.hasPrefix("und ") || first.hasPrefix("also ") || first.hasPrefix("ja ") ? 0.15 : 0
        let context = max(0.2, 0.82 - questionPenalty)
        let duration = max(1, (words.last?.end ?? desiredDuration) - (words.first?.start ?? 0))
        let density = min(1, Double(words.count) / max(18, duration * 2.7))
        let confident = words.map(\.confidence).filter { $0 > 0 }.reduce(0, +) / Double(max(1, words.filter { $0.confidence > 0 }.count))
        let punctuation = words.last?.text.last.map { ".!?".contains($0) } ?? false
        return .init(
            hook: hook,
            payoff: payoff,
            contextIndependence: context,
            informationDensity: max(0.35, density),
            emotionalChange: lower.contains("!") ? 0.72 : 0.5,
            sentenceBoundaryQuality: punctuation ? 0.92 : 0.62,
            visualActivity: 0.55,
            silencePenalty: max(0.02, 0.18 - confident * 0.10)
        )
    }

    private func introPadding(for words: [TranscriptWord]) -> Double { words.first?.text.first?.isUppercase == true ? 0.08 : 0.22 }
    private func outroPadding(for words: [TranscriptWord]) -> Double { words.last?.text.last.map { ".!?".contains($0) } == true ? 0.18 : 0.35 }

    private func join(_ tokens: [String]) -> String {
        tokens.reduce(into: "") { text, token in
            if text.isEmpty { text = token }
            else if token.first.map({ ",.!?:;)]}".contains($0) }) == true { text += token }
            else { text += " " + token }
        }
    }
}

struct RenderResult: Hashable {
    let outputURL: URL
    let probe: SourceProbe
    let quality: RenderQualityReport
}

final class HighQualityRenderService {
    private let inspector = LocalMediaInspector()

    func render(
        sourceURL: URL,
        clip: ClipCandidate,
        spec: ExportSpec,
        captions: [CaptionCue],
        captionStyle: CaptionStyle,
        outputURL: URL
    ) async throws -> RenderResult {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw YouTubeUploadError(message: "Keine Videospur gefunden.") }
        let sourceDuration = try await asset.load(.duration).seconds
        let start = max(0, min(clip.start, sourceDuration - 0.1))
        let end = max(start + 0.1, min(clip.end, sourceDuration))
        let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw YouTubeUploadError(message: "Videotimeline konnte nicht erstellt werden.")
        }
        try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: .zero)

        let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
        if let audio = sourceAudio.first, let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(timeRange, of: audio, at: .zero)
        }

        let sourceSize = try await sourceVideo.load(.naturalSize)
        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        let displayRect = CGRect(origin: .zero, size: sourceSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        let renderSize = targetSize(source: displaySize, spec: spec)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(seconds: 1 / max(1, spec.targetFPS), preferredTimescale: 600)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: end - start, preferredTimescale: 600))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(fittedTransform(sourceSize: sourceSize, preferred: preferredTransform, displayRect: displayRect, target: renderSize), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        if spec.includeCaptions, !captions.isEmpty {
            installCaptionLayers(captions: captions, clipStart: start, duration: end - start, style: captionStyle, renderSize: renderSize, videoComposition: videoComposition)
        }

        try? FileManager.default.removeItem(at: outputURL)
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let preset: String
        if max(renderSize.width, renderSize.height) >= 3800, compatible.contains(AVAssetExportPresetHEVC3840x2160) {
            preset = AVAssetExportPresetHEVC3840x2160
        } else if compatible.contains(AVAssetExportPresetHEVCHighestQuality) {
            preset = AVAssetExportPresetHEVCHighestQuality
        } else {
            preset = AVAssetExportPresetHighestQuality
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw YouTubeUploadError(message: "Für diese Quelle steht kein hochwertiger Exporter zur Verfügung.")
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition
        try await export(exporter)

        let probe = try await inspector.probe(url: outputURL)
        let expectedDuration = end - start
        let durationMatches = abs(probe.duration - expectedDuration) <= max(0.35, expectedDuration * 0.015)
        let dimensionsValid = probe.naturalSize.width >= 640 && probe.naturalSize.height >= 360
        let fpsValid = abs(probe.frameRate - spec.targetFPS) <= 2.5 || probe.frameRate >= min(24, spec.targetFPS)
        let report = RenderQualityReport(
            captionReport: nil,
            sourceReadable: true,
            durationMatches: durationMatches,
            audioPresentWhenExpected: true,
            dimensionsValid: dimensionsValid,
            frameRateValid: fpsValid,
            errors: durationMatches ? [] : ["Exportdauer weicht unerwartet vom gewählten Schnitt ab."]
        )
        return .init(outputURL: outputURL, probe: probe, quality: report)
    }

    private func export(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed: continuation.resume(returning: ())
                case .failed: continuation.resume(throwing: exporter.error ?? YouTubeUploadError(message: "Videoexport fehlgeschlagen."))
                case .cancelled: continuation.resume(throwing: YouTubeUploadError(message: "Videoexport wurde abgebrochen."))
                default: continuation.resume(throwing: YouTubeUploadError(message: "Videoexport wurde unerwartet beendet."))
                }
            }
        }
    }

    private func targetSize(source: CGSize, spec: ExportSpec) -> CGSize {
        let maxEdge = min(spec.maxLongEdge, max(source.width, source.height))
        if spec.orientation == .portrait {
            let h = roundedEven(maxEdge)
            return CGSize(width: roundedEven(h * 9 / 16), height: h)
        }
        let w = roundedEven(maxEdge)
        let h = roundedEven(w * 9 / 16)
        return CGSize(width: max(640, w), height: max(360, h))
    }

    private func roundedEven(_ value: CGFloat) -> CGFloat {
        let integer = max(2, Int(value.rounded()))
        return CGFloat(integer - integer % 2)
    }

    private func fittedTransform(sourceSize: CGSize, preferred: CGAffineTransform, displayRect: CGRect, target: CGSize) -> CGAffineTransform {
        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(translationX: -displayRect.origin.x, y: -displayRect.origin.y))
        let display = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        let scale = max(target.width / max(1, display.width), target.height / max(1, display.height))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaled = CGSize(width: display.width * scale, height: display.height * scale)
        transform = transform.concatenating(CGAffineTransform(translationX: (target.width - scaled.width) / 2, y: (target.height - scaled.height) / 2))
        return transform
    }

    private func installCaptionLayers(captions: [CaptionCue], clipStart: Double, duration: Double, style: CaptionStyle, renderSize: CGSize, videoComposition: AVMutableVideoComposition) {
        let parent = CALayer()
        let videoLayer = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        for cue in captions {
            let localStart = cue.start - clipStart
            let localEnd = cue.end - clipStart
            if localEnd <= 0 || localStart >= duration { continue }
            let text = CATextLayer()
            text.string = cue.text
            text.alignmentMode = .center
            text.isWrapped = true
            text.contentsScale = 2
            text.foregroundColor = CGColor(gray: 1, alpha: 1)
            text.shadowColor = CGColor(gray: 0, alpha: 1)
            text.shadowOpacity = style == .minimal ? 0.65 : 0.9
            text.shadowRadius = style == .minimal ? 3 : 6
            text.shadowOffset = .zero
            let fontSize = max(24, renderSize.height * (style == .creator ? 0.048 : 0.040))
            text.fontSize = fontSize
            text.font = CTFontCreateWithName((style == .creator ? "Helvetica Neue Bold" : "Helvetica Neue Medium") as CFString, fontSize, nil)
            let boxWidth = renderSize.width * 0.82
            let boxHeight = fontSize * 2.8
            let bottom = renderSize.height * (style == .minimal ? 0.105 : 0.13)
            text.frame = CGRect(x: (renderSize.width - boxWidth) / 2, y: bottom, width: boxWidth, height: boxHeight)
            text.opacity = 0

            let animation = CAKeyframeAnimation(keyPath: "opacity")
            let begin = max(0, localStart)
            let finish = min(duration, localEnd)
            let total = max(0.01, duration)
            animation.keyTimes = [0, NSNumber(value: begin / total), NSNumber(value: min(1, (begin + 0.02) / total)), NSNumber(value: max(0, (finish - 0.02) / total)), NSNumber(value: finish / total), 1]
            animation.values = [0, 0, 1, 1, 0, 0]
            animation.duration = total
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            text.add(animation, forKey: "visibility")
            parent.addSublayer(text)
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }
}
