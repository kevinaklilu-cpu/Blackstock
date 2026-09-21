import XCTest
import Foundation
@testable import BlackstockCore

final class ApprovedSourceProviderClientTests:
    XCTestCase {
    override func tearDown() {
        SourceProviderURLProtocol.handler = nil
        super.tearDown()
    }

    func testApprovedProviderResolvesSecureMediaURL()
        async throws {
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            SourceProviderURLProtocol.self
        ]
        let session = URLSession(
            configuration: configuration
        )

        SourceProviderURLProtocol.handler = {
            request in
            XCTAssertEqual(
                request.httpMethod,
                "POST"
            )
            XCTAssertEqual(
                request.value(
                    forHTTPHeaderField:
                        "Authorization"
                ),
                "Bearer token-123"
            )

            let body = try JSONDecoder().decode(
                ApprovedSourceProviderRequest.self,
                from: try XCTUnwrap(
                    SourceProviderURLProtocol.bodyData(
                        from: request
                    )
                )
            )
            XCTAssertEqual(
                body.externalID,
                "video-123"
            )
            XCTAssertEqual(
                body.provider,
                MediaSourceProvider.youtube.rawValue
            )

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type":
                        "application/json"
                ]
            )!
            let data = Data(
                #"{"mediaURL":"https://media.example.com/video.mp4","expiresAt":null}"#
                    .utf8
            )
            return (response, data)
        }

        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(
                string:
                    "https://www.youtube.com/watch?v=video-123"
            )!,
            externalID: "video-123",
            discoveredAt: Date(
                timeIntervalSince1970: 1
            )
        )

        let resolved =
            try await ApprovedSourceProviderClient(
                session: session
            ).resolve(
                source: source,
                endpointURL: URL(
                    string:
                        "https://provider.example.com/resolve"
                )!,
                bearerToken: "token-123"
            )

        XCTAssertEqual(
            resolved.mediaURL.absoluteString,
            "https://media.example.com/video.mp4"
        )
    }

    func testProviderRejectsNonHTTPSMediaURL()
        async throws {
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            SourceProviderURLProtocol.self
        ]
        let session = URLSession(
            configuration: configuration
        )

        SourceProviderURLProtocol.handler = {
            request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type":
                        "application/json"
                ]
            )!
            return (
                response,
                Data(
                    #"{"mediaURL":"http://media.example.com/video.mp4","expiresAt":null}"#
                        .utf8
                )
            )
        }

        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(
                string:
                    "https://www.youtube.com/watch?v=x"
            )!,
            externalID: "x",
            discoveredAt: Date()
        )

        do {
            _ = try await ApprovedSourceProviderClient(
                session: session
            ).resolve(
                source: source,
                endpointURL: URL(
                    string:
                        "https://provider.example.com/resolve"
                )!,
                bearerToken: nil
            )
            XCTFail("Expected insecure URL rejection")
        } catch let error as
            ApprovedSourceProviderError {
            XCTAssertEqual(
                error,
                .insecureMediaURL
            )
        }
    }
}

private final class SourceProviderURLProtocol:
    URLProtocol {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (
            HTTPURLResponse,
            Data
        ))?

    static func bodyData(
        from request: URLRequest
    ) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer =
            UnsafeMutablePointer<UInt8>.allocate(
                capacity: bufferSize
            )
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(
                buffer,
                maxLength: bufferSize
            )
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler =
                Self.handler else {
            XCTFail("Missing URLProtocol handler")
            return
        }

        do {
            let (response, data) =
                try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(
                self,
                didLoad: data
            )
            client?.urlProtocolDidFinishLoading(
                self
            )
        } catch {
            client?.urlProtocol(
                self,
                didFailWithError: error
            )
        }
    }

    override func stopLoading() {}
}
