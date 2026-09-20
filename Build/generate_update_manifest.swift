#!/usr/bin/env swift

import CryptoKit
import Foundation

enum ManifestToolError: Error, CustomStringConvertible {
    case missingArgument(String)
    case invalidBuild
    case invalidPackageURL
    case packageURLMustUseHTTPS
    case invalidSourceCommitSHA
    case packageMissing
    case missingPrivateKey
    case invalidPrivateKey
    case outputDirectoryMissing

    var description: String {
        switch self {
        case .missingArgument(let name):
            return "Fehlendes Argument: \(name)"
        case .invalidBuild:
            return "Build muss eine positive Ganzzahl sein."
        case .invalidPackageURL:
            return "Paket-URL ist ungültig."
        case .packageURLMustUseHTTPS:
            return "Paket-URL muss HTTPS verwenden."
        case .invalidSourceCommitSHA:
            return "Source-Commit-SHA muss aus genau 40 Hex-Zeichen bestehen."
        case .packageMissing:
            return "Das angegebene .pkg existiert nicht."
        case .missingPrivateKey:
            return "BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64 ist nicht gesetzt."
        case .invalidPrivateKey:
            return "Der Update-Private-Key ist ungültig."
        case .outputDirectoryMissing:
            return "Das Ausgabeverzeichnis existiert nicht."
        }
    }
}

struct Manifest: Codable {
    let version: String
    let build: Int
    let packageURL: URL
    let sha256: String
    let sourceCommitSHA: String
    let publishedAt: Date
    let signature: String

    var signedPayload: Data {
        let timestamp = ISO8601DateFormatter().string(from: publishedAt)
        return Data(
            [
                version,
                String(build),
                packageURL.absoluteString,
                sha256.lowercased(),
                sourceCommitSHA.lowercased(),
                timestamp
            ]
            .joined(separator: "\n")
            .utf8
        )
    }

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case packageURL
        case sha256
        case sourceCommitSHA
        case publishedAt
        case signature
    }
}

func isProductionHTTPSURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
          var host = url.host?.lowercased(),
          !host.isEmpty,
          url.user == nil,
          url.password == nil,
          url.fragment == nil else {
        return false
    }
    while host.hasSuffix(".") {
        host.removeLast()
    }
    guard !host.isEmpty else {
        return false
    }
    return host != "localhost"
        && host != "::1"
        && !host.hasPrefix("127.")
        && !host.hasSuffix(".local")
        && !host.hasSuffix(".invalid")
        && !host.hasSuffix(".example")
        && !host.hasSuffix(".test")
}

func value(after flag: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else {
        throw ManifestToolError.missingArgument(flag)
    }
    return arguments[index + 1]
}

func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
        let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let packagePath = try value(after: "--package", in: arguments)
    let rawPackageURL = try value(after: "--package-url", in: arguments)
    let version = try value(after: "--version", in: arguments)
    let rawBuild = try value(after: "--build", in: arguments)
    let rawSourceCommitSHA = try value(
        after: "--source-commit-sha",
        in: arguments
    )
    let outputPath = try value(after: "--output", in: arguments)

    guard let build = Int(rawBuild), build > 0 else {
        throw ManifestToolError.invalidBuild
    }
    guard let packageURL = URL(string: rawPackageURL) else {
        throw ManifestToolError.invalidPackageURL
    }
    guard packageURL.scheme?.lowercased() == "https" else {
        throw ManifestToolError.packageURLMustUseHTTPS
    }
    guard isProductionHTTPSURL(packageURL) else {
        throw ManifestToolError.invalidPackageURL
    }
    guard rawSourceCommitSHA.count == 40,
          rawSourceCommitSHA.allSatisfy({ $0.isHexDigit }) else {
        throw ManifestToolError.invalidSourceCommitSHA
    }
    let sourceCommitSHA = rawSourceCommitSHA.lowercased()

    let packageFileURL = URL(fileURLWithPath: packagePath)
    guard FileManager.default.fileExists(atPath: packageFileURL.path) else {
        throw ManifestToolError.packageMissing
    }

    guard let privateKeyBase64 = ProcessInfo.processInfo.environment[
        "BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64"
    ], !privateKeyBase64.isEmpty else {
        throw ManifestToolError.missingPrivateKey
    }
    guard let privateKeyData = Data(base64Encoded: privateKeyBase64),
          let privateKey = try? Curve25519.Signing.PrivateKey(
            rawRepresentation: privateKeyData
          ) else {
        throw ManifestToolError.invalidPrivateKey
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    let outputDirectory = outputURL.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: outputDirectory.path) else {
        throw ManifestToolError.outputDirectoryMissing
    }

    let publishedAt = Date()
    let digest = try sha256(of: packageFileURL)
    let unsigned = Manifest(
        version: version,
        build: build,
        packageURL: packageURL,
        sha256: digest,
        sourceCommitSHA: sourceCommitSHA,
        publishedAt: publishedAt,
        signature: ""
    )
    let signature = try privateKey.signature(for: unsigned.signedPayload)
    let manifest = Manifest(
        version: version,
        build: build,
        packageURL: packageURL,
        sha256: digest,
        sourceCommitSHA: sourceCommitSHA,
        publishedAt: publishedAt,
        signature: signature.base64EncodedString()
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(manifest)
    try data.write(to: outputURL, options: [.atomic])

    print("Created signed update manifest: \(outputURL.path)")
} catch {
    fputs("Update manifest generation failed: \(error)\n", stderr)
    exit(1)
}
