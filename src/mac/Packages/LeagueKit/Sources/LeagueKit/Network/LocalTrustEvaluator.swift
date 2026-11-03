import Foundation
import os
import Security

/// Validates the certificates of Riot's local servers (LCU, Live Client) against the bundled
/// `riotgames.pem` – and nothing else.
///
/// Uses `SecPolicyCreateBasicX509` instead of the SSL policy: the LCU leaf certificate is valid
/// for 100 years, which Apple's TLS rules reject. Host and port are therefore checked here.
public struct LocalTrustEvaluator: Sendable {
    public static let allowedHost = "127.0.0.1"

    private let anchors: [SecCertificate]

    public init(anchors: [SecCertificate]) {
        self.anchors = anchors
    }

    /// Loads the bundled Riot root CA.
    public static func bundled() throws -> LocalTrustEvaluator {
        guard let url = Bundle.module.url(forResource: "riotgames", withExtension: "pem") else {
            throw LocalTrustError.missingAnchor
        }
        return try LocalTrustEvaluator(anchors: PEM.certificates(in: Data(contentsOf: url)))
    }

    public func evaluate(_ trust: SecTrust, host: String, port: Int, expectedPorts: Set<Int>) -> Bool {
        guard host == Self.allowedHost, expectedPorts.contains(port), !anchors.isEmpty,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}

public enum LocalTrustError: Error {
    case missingAnchor
    case invalidPEM
}

enum PEM {
    static func certificates(in data: Data) throws -> [SecCertificate] {
        guard let text = String(data: data, encoding: .utf8) else { throw LocalTrustError.invalidPEM }
        let blocks = text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst()
        let certificates = blocks.compactMap { block -> SecCertificate? in
            guard let body = block.components(separatedBy: "-----END CERTIFICATE-----").first,
                  let der = Data(base64Encoded: body, options: .ignoreUnknownCharacters)
            else { return nil }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
        guard !certificates.isEmpty else { throw LocalTrustError.invalidPEM }
        return certificates
    }
}

/// URLSession delegate that applies `LocalTrustEvaluator` to server-trust challenges.
/// The allowed ports are updated when the LCU restarts on a new port.
public final class LocalTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    private let evaluator: LocalTrustEvaluator
    private let ports: OSAllocatedUnfairLock<Set<Int>>

    public init(evaluator: LocalTrustEvaluator, ports: Set<Int>) {
        self.evaluator = evaluator
        self.ports = OSAllocatedUnfairLock(initialState: ports)
    }

    public func setAllowedPorts(_ newPorts: Set<Int>) {
        ports.withLock { $0 = newPorts }
    }

    public func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        let allowed = ports.withLock { $0 }
        guard evaluator.evaluate(trust, host: space.host, port: space.port, expectedPorts: allowed) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
