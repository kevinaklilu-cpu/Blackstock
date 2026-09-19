#if os(macOS)
import Foundation
import Network

final class LoopbackOAuthServer: @unchecked Sendable {
    enum ServerError: Error {
        case failed(NWError)
        case cancelled
        case invalidRequest
        case noPort
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "de.blackstock.oauth.loopback")
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackURL: URL?
    private var terminalError: Error?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: .any
        )
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.readyContinuation = continuation
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener.port else {
                            self.finishReady(.failure(ServerError.noPort))
                            return
                        }
                        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2/callback")!
                        self.finishReady(.success(url))
                    case .failed(let error):
                        self.terminalError = ServerError.failed(error)
                        self.finishReady(.failure(ServerError.failed(error)))
                        self.finishCallback(.failure(ServerError.failed(error)))
                    case .cancelled:
                        if self.callbackURL == nil && self.terminalError == nil {
                            self.terminalError = ServerError.cancelled
                            self.finishCallback(.failure(ServerError.cancelled))
                        }
                    default:
                        break
                    }
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let url = self.callbackURL {
                    continuation.resume(returning: url)
                } else if let error = self.terminalError {
                    continuation.resume(throwing: error)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func cancel() {
        queue.async { self.listener.cancel() }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(
                    separatedBy: "\r\n"
                  ).first else {
                self.reject(connection)
                return
            }

            let fields = firstLine.split(separator: " ")
            guard fields.count >= 2,
                  fields[0] == "GET" else {
                self.reject(connection)
                return
            }
            let target = String(fields[1])
            guard let port = self.listener.port,
                  let url = URL(
                    string: "http://127.0.0.1:\(port.rawValue)\(target)"
                  ),
                  url.path == "/oauth2/callback" else {
                self.reject(connection)
                return
            }

            let body = """
            <!doctype html><html lang="de"><meta charset="utf-8">
            <title>Blackstock</title>
            <body style="font-family:-apple-system;padding:48px;background:#111;color:#fff">
            <h1>Google verbunden</h1><p>Du kannst dieses Fenster schließen und zu Blackstock zurückkehren.</p>
            </body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            self.callbackURL = url
            self.finishCallback(.success(url))
            self.listener.cancel()
        }
    }

    private func reject(_ connection: NWConnection) {
        let response = """
        HTTP/1.1 404 Not Found\r
        Content-Length: 0\r
        Connection: close\r
        \r
        """
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func finishReady(_ result: Result<URL, Error>) {
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume(with: result)
    }

    private func finishCallback(_ result: Result<URL, Error>) {
        guard let continuation = callbackContinuation else { return }
        callbackContinuation = nil
        continuation.resume(with: result)
    }
}
#endif
