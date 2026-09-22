import Foundation

public enum YouTubeDownloadRequest {
    public static func accepts(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    public static func arguments(url: URL, output: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--break-match-filters", "!is_live", "--no-overwrites", "--newline",
         "--no-colors", "--write-info-json", "--no-simulate", "--progress", "--socket-timeout", "30",
         "--retries", "3", "--format", "bestvideo[ext=mp4][vcodec^=avc1][height<=1080],bestaudio[ext=m4a]",
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
