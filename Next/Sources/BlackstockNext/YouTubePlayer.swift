import SwiftUI
import WebKit

struct YouTubePreview: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let current = webView.url?.absoluteString ?? ""
        guard !current.contains("/embed/\(videoID)") else { return }
        guard let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1") else { return }
        webView.load(URLRequest(url: url))
    }
}
