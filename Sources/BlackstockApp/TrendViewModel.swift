#if os(macOS)
import Foundation
import BlackstockCore
@MainActor final class TrendViewModel: ObservableObject {
    @Published var query = ""
    @Published var items: [TrendSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFormat: VideoFormat?
    private var nextPageToken: String?
    private var task: Task<Void, Never>?
    private var currentKey = ""
    var visibleItems: [TrendSignal] { guard let selectedFormat else { return items }; return items.filter { $0.recommendedFormat == selectedFormat } }
    func search(apiKey: String, channel: ChannelSnapshot, reset: Bool = true) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines), key = "\(normalized)|\(channel.recentTopics.joined(separator: ","))"
        if reset { nextPageToken = nil; currentKey = key }; task?.cancel()
        task = Task { [weak self] in guard let self else { return }; if reset { try? await Task.sleep(for: .milliseconds(250)) }; guard !Task.isCancelled else { return }; await load(apiKey: apiKey, channel: channel, reset: reset, key: key) }
    }
    func loadMoreIfNeeded(current item: TrendSignal, apiKey: String, channel: ChannelSnapshot) {
        guard let index = visibleItems.firstIndex(where: { $0.id == item.id }), index >= max(visibleItems.count - 6, 0), nextPageToken != nil, !isLoading else { return }; search(apiKey: apiKey, channel: channel, reset: false)
    }
    private func load(apiKey: String, channel: ChannelSnapshot, reset: Bool, key: String) async {
        guard !apiKey.isEmpty else { errorMessage = "Trage in Einstellungen einen YouTube Data API Key ein, damit Trends live geladen werden."; return }
        isLoading = true; defer { isLoading = false }
        do {
            let repo = TrendRepository(searcher: YouTubeDataAPIClient(apiKey: apiKey)); let page = try await repo.trends(query: query, pageToken: reset ? nil : nextPageToken, channel: channel)
            guard !Task.isCancelled, reset || key == currentKey else { return }
            if reset { items = page.items } else { let known = Set(items.map(\.id)); items.append(contentsOf: page.items.filter { !known.contains($0.id) }) }
            nextPageToken = page.nextPageToken; errorMessage = nil
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}
#endif
