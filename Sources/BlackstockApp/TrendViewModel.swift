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
    private var repositoryAccessToken = ""

    var visibleItems: [TrendSignal] {
        items.filter { signal in
            (selectedFormat == nil || signal.recommendedFormat == selectedFormat) && durationFilter.contains(seconds: signal.video.durationSeconds)
        }
    }

    func search(accessToken: String, regionCode: String, channel: ChannelSnapshot, reset: Bool = true) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(normalized)|\(regionCode)|\(channel.id)"
        if reset { nextPageToken = nil; currentKey = key }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            if reset { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            await load(accessToken: accessToken, regionCode: regionCode, channel: channel, reset: reset, key: key)
        }
    }

    func loadMoreIfNeeded(current item: TrendSignal, accessToken: String, regionCode: String, channel: ChannelSnapshot) {
        guard let index = visibleItems.firstIndex(where: { $0.id == item.id }), index >= max(visibleItems.count - 6, 0), nextPageToken != nil, !isLoading else { return }
        search(accessToken: accessToken, regionCode: regionCode, channel: channel, reset: false)
    }

    private func repositoryFor(accessToken: String) -> TrendRepository {
        if repository == nil || repositoryAccessToken != accessToken {
            repository = TrendRepository(provider: YouTubeDataAPIClient(accessToken: accessToken))
            repositoryAccessToken = accessToken
        }
        return repository!
    }

    private func load(accessToken: String, regionCode: String, channel: ChannelSnapshot, reset: Bool, key: String) async {
        guard !accessToken.isEmpty else { errorMessage = "Verbinde deinen YouTube-Kanal, damit Blackstock reale YouTube-Daten laden kann."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repositoryFor(accessToken: accessToken).trends(query: query, regionCode: regionCode.isEmpty ? nil : regionCode, pageToken: reset ? nil : nextPageToken, channel: channel)
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
