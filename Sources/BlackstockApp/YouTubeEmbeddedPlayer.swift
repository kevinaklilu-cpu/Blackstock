#if os(macOS)
import SwiftUI
import WebKit

struct YouTubeEmbeddedPlayer: NSViewRepresentable {
    let videoID: String

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoID != videoID else { return }
        context.coordinator.loadedVideoID = videoID

        let safeVideoID = videoID.filter { character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }

        let html = #"""
        <!doctype html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              background: #000;
              overflow: hidden;
            }
            iframe {
              width: 100%;
              height: 100%;
              border: 0;
            }
          </style>
        </head>
        <body>
          <iframe
            src="https://www.youtube-nocookie.com/embed/\#(safeVideoID)?playsinline=1&rel=0"
            title="YouTube Video"
            allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """#

        webView.loadHTMLString(
            html,
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
    }
}
#endif
