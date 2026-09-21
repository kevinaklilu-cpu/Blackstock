#if os(macOS)
import AppKit
import SwiftUI
import WebKit

struct YouTubeEmbeddedPlayer: NSViewRepresentable {
    let videoID: String

    final class Coordinator:
        NSObject,
        WKNavigationDelegate {
        var loadedVideoID: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction:
                WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .allow
            }

            if navigationAction.navigationType == .linkActivated,
               let host = url.host?.lowercased(),
               host.contains("youtube.com"),
               !url.path.hasPrefix("/embed/") {
                NSWorkspace.shared.open(url)
                return .cancel
            }

            return .allow
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation:
                WKNavigation!,
            withError error: Error
        ) {
            showFallback(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            showFallback(in: webView)
        }

        private func showFallback(
            in webView: WKWebView
        ) {
            let html = #"""
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport"
                    content="width=device-width, initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  background: #0a0a0a;
                  color: white;
                  font-family: -apple-system, sans-serif;
                }
                body {
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  text-align: center;
                }
                div { max-width: 420px; padding: 24px; }
                h3 { margin: 0 0 8px; }
                p {
                  margin: 0;
                  color: #b9b9b9;
                  line-height: 1.45;
                  font-size: 13px;
                }
              </style>
            </head>
            <body>
              <div>
                <h3>YouTube-Vorschau nicht verfügbar</h3>
                <p>
                  Öffne das Video über „Auf YouTube ansehen“.
                </p>
              </div>
            </body>
            </html>
            """#
            webView.loadHTMLString(
                html,
                baseURL: URL(
                    string: "https://blackstock.app/"
                )
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(
        context: Context
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = true
        configuration.applicationNameForUserAgent =
            "Blackstock YouTube Player"

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.navigationDelegate = context.coordinator
        webView.setValue(
            false,
            forKey: "drawsBackground"
        )
        webView.enclosingScrollView?
            .hasVerticalScroller = false
        webView.enclosingScrollView?
            .hasHorizontalScroller = false
        return webView
    }

    func updateNSView(
        _ webView: WKWebView,
        context: Context
    ) {
        let safeVideoID = videoID.filter {
            $0.isLetter
            || $0.isNumber
            || $0 == "_"
            || $0 == "-"
        }
        guard !safeVideoID.isEmpty,
              context.coordinator.loadedVideoID
                != safeVideoID else {
            return
        }
        context.coordinator.loadedVideoID =
            safeVideoID

        var components = URLComponents(
            string:
                "https://www.youtube.com/embed/"
                + safeVideoID
        )!
        components.queryItems = [
            .init(name: "playsinline", value: "1"),
            .init(name: "rel", value: "0"),
            .init(name: "enablejsapi", value: "1"),
            .init(
                name: "origin",
                value: "https://blackstock.app"
            )
        ]
        guard let url = components.url else {
            return
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        request.setValue(
            "https://blackstock.app/",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "de-DE,de;q=0.9,en;q=0.8",
            forHTTPHeaderField: "Accept-Language"
        )
        webView.load(request)
    }
}
#endif
