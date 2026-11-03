import Foundation
@testable import LeagueKit
import Security
import Testing

/// Uses the certificate chain recorded from the real LCU (tests/fixtures/lcu/lcu-chain.pem).
struct LocalTrustEvaluatorTests {
    private func recordedTrust() throws -> SecTrust {
        let chain = try PEM.certificates(in: Fixture.data("lcu/lcu-chain.pem"))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates([chain[0]] as CFArray, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func bundledAnchorLoads() throws {
        _ = try LocalTrustEvaluator.bundled()
    }

    @Test func acceptsRecordedLCUChain() throws {
        let evaluator = try LocalTrustEvaluator.bundled()
        #expect(try evaluator.evaluate(recordedTrust(), host: "127.0.0.1", port: 49215, expectedPorts: [49215]))
    }

    @Test func rejectsOtherHostOrPort() throws {
        let evaluator = try LocalTrustEvaluator.bundled()
        #expect(try !evaluator.evaluate(recordedTrust(), host: "localhost", port: 49215, expectedPorts: [49215]))
        #expect(try !evaluator.evaluate(recordedTrust(), host: "127.0.0.1", port: 443, expectedPorts: [49215]))
    }

    @Test func rejectsWithoutMatchingAnchor() throws {
        // The leaf itself is not a CA, so anchoring on it must not validate anything else.
        let leaf = try PEM.certificates(in: Fixture.data("lcu/lcu-chain.pem"))[0]
        let evaluator = LocalTrustEvaluator(anchors: [leaf])
        let other = try PEM.certificates(in: Fixture.data("lcu/lcu-chain.pem"))[1]
        var trust: SecTrust?
        SecTrustCreateWithCertificates([other] as CFArray, SecPolicyCreateBasicX509(), &trust)
        #expect(try !evaluator.evaluate(#require(trust), host: "127.0.0.1", port: 1, expectedPorts: [1]))
    }

    @Test func emptyAnchorsRejectEverything() throws {
        #expect(try !LocalTrustEvaluator(anchors: []).evaluate(
            recordedTrust(),
            host: "127.0.0.1",
            port: 1,
            expectedPorts: [1]
        ))
    }

    @Test func pemParserRejectsGarbage() {
        #expect(throws: LocalTrustError.self) { try PEM.certificates(in: Data("nope".utf8)) }
    }
}
