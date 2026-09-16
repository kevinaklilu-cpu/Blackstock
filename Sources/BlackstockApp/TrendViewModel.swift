#if os(macOS)
import Foundation
import BlackstockCore

@MainActor final class TrendViewModel: ObservableObject {
    @Published var query = ""
    @Published var items: [TrendSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFormat: VideoFormat?
    @Published var durationFilter: VideoDurationFilter = .all

    private var nextPageToken: String?
    private var task: Task<Void, Never>?
    private var currentKey = ""
    private var repository: TrendRepository?
    private var repositoryAPIKey = ""

    var visibleItems: [TrendSignal] {
        items.filter { signal in
            (selectedFormat == nil || signal.recommendedFormat == selectedFormat) && durationFilter.contains(seconds: signal.video.durationSeconds)
        }
    }

    func search(apiKey: String, regionCode: String, channel: ChannelSnapshot, reset: Bool = true) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(normalized)|\(regionCode)|\(channel.id)"
        if reset { nextPageToken = nil; currentKey = key }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            if reset { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            await load(apiKey: apiKey, regionCode: regionCode, channel: channel, reset: reset, key: key)
        }
    }

    func loadMoreIfNeeded(current item: TrendSignal, apiKey: String, regionCode: String, channel: ChannelSnapshot) {
        guard let index = visibleItems.firstIndex(where: { $0.id == item.id }), index >= max(visibleItems.count - 6, 0), nextPageToken != nil, !isLoading else { return }
        search(apiKey: apiKey, regionCode: regionCode, channel: channel, reset: false)
    }

    private func repositoryFor(apiKey: String) -> TrendRepository {
        if repository == nil || repositoryAPIKey != apiKey {
            repository = TrendRepository(provider: YouTubeDataAPIClient(apiKey: apiKey))
            repositoryAPIKey = apiKey
        }
        return repository!
    }

    private func load(apiKey: String, regionCode: String, channel: ChannelSnapshot, reset: Bool, key: String) async {
        guard !apiKey.isEmpty else { errorMessage = "Trage in Einstellungen einen YouTube Data API Key ein, damit Trends live geladen werden."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repositoryFor(apiKey: apiKey).trends(query: query, regionCode: regionCode.isEmpty ? nil : regionCode, pageToken: reset ? nil : nextPageToken, channel: channel)
            guard !Task.isCancelled, reset || key == currentKey else { return }
            if reset { items = page.items }
            else { let known = Set(items.map(\.id)); items.append(contentsOf: page.items.filter { !known.contains($0.id) }) }
            nextPageToken = page.nextPageToken
            errorMessage = nil
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
#endif
