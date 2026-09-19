#!/usr/bin/env swift

import CryptoKit
import Foundation

enum UpdateKeyPairError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidPrivateKey
    case invalidPublicKey
    case mismatch

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Fehlende Umgebungsvariable: \(name)"
        case .invalidPrivateKey:
            return "Der private Update-Signaturschlüssel ist ungültig."
        case .invalidPublicKey:
            return "Der öffentliche Update-Prüfschlüssel ist ungültig."
        case .mismatch:
            return "Privater Update-Signaturschlüssel und öffentlicher Update-Prüfschlüssel gehören nicht zusammen."
        }
    }
}

func requiredEnvironment(_ name: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[name],
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw UpdateKeyPairError.missingEnvironment(name)
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
    let privateBase64 = try requiredEnvironment(
        "BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64"
    )
    let publicBase64 = try requiredEnvironment(
        "BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64"
    )

    guard let privateData = Data(base64Encoded: privateBase64),
          privateData.count == 32,
          let privateKey = try? Curve25519.Signing.PrivateKey(
            rawRepresentation: privateData
          ) else {
        throw UpdateKeyPairError.invalidPrivateKey
    }

    guard let publicData = Data(base64Encoded: publicBase64),
          publicData.count == 32,
          (try? Curve25519.Signing.PublicKey(
            rawRepresentation: publicData
          )) != nil else {
        throw UpdateKeyPairError.invalidPublicKey
    }

    let derivedPublic = privateKey.publicKey.rawRepresentation
    guard derivedPublic == publicData else {
        throw UpdateKeyPairError.mismatch
    }

    print("BLACKSTOCK_UPDATE_KEY_PAIR_PASS")
} catch {
    fputs("BLACKSTOCK_UPDATE_KEY_PAIR_FAIL: \(error)\n", stderr)
    exit(1)
}
