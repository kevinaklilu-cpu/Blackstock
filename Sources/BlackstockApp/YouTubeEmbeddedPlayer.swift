#if os(macOS)
import AppKit
import SwiftUI
import WebKit

struct YouTubeEmbeddedPlayer: NSViewRepresentable {
    let videoID: String

    final class Coordinator:
        NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler {
        var loadedVideoID: String?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "blackstockYouTube" else {
                return
            }
            let videoID: String
            if let payload = message.body as? [String: Any],
               let value = payload["videoID"] as? String {
                videoID = value
            } else if let value = message.body as? String {
                videoID = value
            } else {
                return
            }

            let safeID = videoID.filter {
                $0.isLetter
                || $0.isNumber
                || $0 == "_"
                || $0 == "-"
            }
            guard let url = URL(
                string:
                    "https://www.youtube.com/watch?v="
                    + safeID
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction:
                WKNavigationAction,
            decisionHandler:
                @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated,
               let host = url.host,
               host.contains("youtube.com") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(
            context.coordinator,
            name: "blackstockYouTube"
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = true
        configuration.userContentController = controller
        configuration.applicationNameForUserAgent =
            "Blackstock"

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

    static func dismantleNSView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(
                forName: "blackstockYouTube"
            )
    }

    func updateNSView(
        _ webView: WKWebView,
        context: Context
    ) {
        guard context.coordinator.loadedVideoID
            != videoID else {
            return
        }
        context.coordinator.loadedVideoID = videoID

        let safeVideoID = videoID.filter {
            $0.isLetter
            || $0.isNumber
            || $0 == "_"
            || $0 == "-"
        }

        let html = #"""
        <!doctype html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            * { box-sizing: border-box; }
            html, body {
              margin: 0;
              width: 100%;
              height: 100%;
              background: #000;
              overflow: hidden;
              font-family:
                -apple-system,
                BlinkMacSystemFont,
                "Segoe UI",
                sans-serif;
            }
            #player {
              width: 100%;
              height: 100%;
            }
            #fallback {
              display: none;
              width: 100%;
              height: 100%;
              padding: 24px;
              align-items: center;
              justify-content: center;
              text-align: center;
              background:
                radial-gradient(
                  circle at center,
                  #202020 0%,
                  #090909 72%
                );
              color: white;
            }
            .card {
              max-width: 430px;
            }
            .mark {
              width: 54px;
              height: 38px;
              margin: 0 auto 14px;
              border-radius: 12px;
              background: #ff0000;
              display: flex;
              align-items: center;
              justify-content: center;
              font-size: 24px;
              font-weight: 800;
            }
            h2 {
              margin: 0 0 8px;
              font-size: 18px;
            }
            p {
              margin: 0 0 16px;
              color: #bdbdbd;
              font-size: 13px;
              line-height: 1.45;
            }
            button {
              border: 0;
              border-radius: 9px;
              padding: 10px 15px;
              background: #ff0000;
              color: white;
              font-weight: 700;
              cursor: pointer;
            }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <div id="fallback">
            <div class="card">
              <div class="mark">B</div>
              <h2>Wiedergabe nur auf YouTube möglich</h2>
              <p id="reason">
                Dieses Video kann nicht in Blackstock eingebettet abgespielt werden.
              </p>
              <button onclick="openOnYouTube()">
                Auf YouTube ansehen
              </button>
            </div>
          </div>

          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            const videoID = "#(safeVideoID)";
            let player = null;

            function openOnYouTube() {
              window.webkit.messageHandlers
                .blackstockYouTube
                .postMessage({ videoID: videoID });
            }

            function showFallback(code) {
              const reason = document.getElementById("reason");
              if (code === 101 || code === 150) {
                reason.textContent =
                  "Der Rechteinhaber erlaubt die Wiedergabe dieses Videos nicht in eingebetteten Playern.";
              } else if (code === 153) {
                reason.textContent =
                  "YouTube konnte diesen eingebetteten Player nicht eindeutig identifizieren.";
              } else {
                reason.textContent =
                  "YouTube kann dieses Video in Blackstock gerade nicht wiedergeben.";
              }

              document.getElementById("player").style.display = "none";
              document.getElementById("fallback").style.display = "flex";
            }

            function onYouTubeIframeAPIReady() {
              player = new YT.Player("player", {
                width: "100%",
                height: "100%",
                videoId: videoID,
                playerVars: {
                  playsinline: 1,
                  rel: 0,
                  origin: "https://blackstock.app"
                },
                events: {
                  onError: function(event) {
                    showFallback(event.data);
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """#

        webView.loadHTMLString(
            html,
            baseURL: URL(
                string: "https://blackstock.app"
            )
        )
    }
}
#endif
