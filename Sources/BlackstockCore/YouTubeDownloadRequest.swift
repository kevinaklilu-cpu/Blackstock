import Foundation

public enum YouTubeDownloadRequest {
    // Bump whenever the media acceptance/normalization contract changes so a
    // previously cached file can never bypass the current A/V sync checks.
    public static let recoveryIdentityVersion = "av-sync-v3-zero-timeline"

    public static func accepts(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    public static func arguments(url: URL, output: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--break-match-filters", "!is_live", "--no-overwrites", "--newline",
         "--no-colors", "--write-info-json", "--no-simulate", "--progress", "--socket-timeout", "30",
         "--retries", "5", "--fragment-retries", "5", "--format", "best[ext=mp4][vcodec^=avc1][acodec!=none][height<=1080][fps<=30]/(bestvideo[ext=mp4][vcodec^=avc1][height<=1080][fps<=30],bestaudio[ext=m4a])",
         "--progress-template", "download:BLACKSTOCK_PROGRESS:%(progress._percent_str)s",
         "--output", output.path, "--", url.absoluteString]
    }

    public static func progress(_ line: String) -> Double? {
        let prefix = "BLACKSTOCK_PROGRESS:"
        guard line.hasPrefix(prefix),
              let value = Double(line.dropFirst(prefix.count)
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return nil }
        return min(max(value / 100, 0), 1)
    }
}
