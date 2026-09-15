import Foundation

@main
struct NextCoreTests {
    static func main() {
        assert(abs(YouTubePublicClient.parseDuration("PT1H2M3S") - 3723) < 0.01)
        assert(abs(YouTubePublicClient.parseDuration("PT45S") - 45) < 0.01)
        let timestamps = YouTubePublicClient.extractTimestamps(from: "Best part 1:23 and 01:02:03")
        assert(timestamps.contains(83) && timestamps.contains(3723))

        let now = Date()
        let recent = [
            PublicVideo(videoID: "a", title: "iPhone Kamera Test und Vergleich", description: "Apple Smartphone Kamera im Alltag", channelTitle: "Tech", channelID: "c", publishedAt: now, thumbnailURL: nil, viewCount: 1000, likeCount: 10, commentCount: 5, durationSeconds: 600, categoryID: "28"),
            PublicVideo(videoID: "b", title: "Apple iPhone Akkutest", description: "Smartphone Akku und Kamera", channelTitle: "Tech", channelID: "c", publishedAt: now, thumbnailURL: nil, viewCount: 1000, likeCount: 10, commentCount: 5, durationSeconds: 600, categoryID: "28")
        ]
        let dna = ChannelDNAService.build(from: recent)
        assert(dna.sampleSize == 2 && !dna.keywords.isEmpty)
        let matching = PublicVideo(videoID: "x", title: "iPhone Kamera überrascht", description: "Apple Smartphone", channelTitle: "Other", channelID: "d", publishedAt: now.addingTimeInterval(-3600), thumbnailURL: nil, viewCount: 100000, likeCount: 100, commentCount: 50, durationSeconds: 500, categoryID: "28")
        let unrelated = PublicVideo(videoID: "y", title: "Fußball Bundesliga Spiel", description: "Tore und Tabelle", channelTitle: "Sport", channelID: "e", publishedAt: now.addingTimeInterval(-3600), thumbnailURL: nil, viewCount: 100000, likeCount: 100, commentCount: 50, durationSeconds: 500, categoryID: "17")
        assert(ChannelDNAService.fit(video: matching, dna: dna) > ChannelDNAService.fit(video: unrelated, dna: dna))

        let transcript = (0..<20).map { index in TranscriptSegment(start: Double(index) * 3.0, duration: 2.7, text: index == 4 ? "Aber warum ist das wirklich so wichtig?" : "Hier erklären wir den nächsten konkreten Punkt", confidence: 0.9) }
        let moments = MomentEngine.rank(transcript: transcript, mediaDuration: 70)
        assert(!moments.isEmpty)
        assert(moments.allSatisfy { $0.duration >= 18 && $0.duration <= 58 })
        let ranked = OpportunityEngine.rank(videos: [matching, unrelated], dna: dna, now: now)
        assert(ranked.first?.video.videoID == "x")
        print("BLACKSTOCK_MARKET_READY_CORE_TESTS_OK")
    }
}
