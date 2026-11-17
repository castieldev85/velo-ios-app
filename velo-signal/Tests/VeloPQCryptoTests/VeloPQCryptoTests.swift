// Vettori: proto-XEP OMEMO-PQXDH §5.5.2 / §4.9.1 / §4.6.3 e NIST SP 800-185 (KMAC256).
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import VeloPQCrypto

final class VeloPQCryptoTests: XCTestCase {
    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
    private func unhex(_ s: String) -> [UInt8] {
        var out = [UInt8](); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }

    func testKmacNistSample4() {
        let key = Array(UInt8(0x40)...UInt8(0x5F))
        let out = Kmac.kmac256(key: key, data: [0, 1, 2, 3], customization: Array("My Tagged Application".utf8), outputLength: 64)
        XCTAssertEqual(hex(out), "20c570c31346f703c9ac36c61c03cb64c3970d0cfc787e9b79599d273a68d2f7f69d4cc3de9d104a351689f27cf6f5951f0103f33f4f24871024d9c27773a8dd")
    }

    func testKmacNistSample6() {
        let key = Array(UInt8(0x40)...UInt8(0x5F))
        let data = (0..<200).map { UInt8($0) }
        let out = Kmac.kmac256(key: key, data: data, customization: Array("My Tagged Application".utf8), outputLength: 64)
        XCTAssertEqual(hex(out), "b58618f71f92e1d56c1b8c55ddd7cd188b97b4ca4d99831eb2699a837da2e4d970fbacfde50033aea585f1a2708510c32d07880801bd182898fe476876fc8965")
    }

    // Proto-XEP §5.5.2, con le etichette "monocles:" della specifica (la Velo usa "velo:").
    func testProtoXepCommitAndPayloadKeys() {
        let mk = [UInt8](repeating: 0x07, count: 32)
        let binding = Omemo2Payload.contextBinding(from: "alice@example.com", to: "bob@example.com", sid: 42)
        XCTAssertEqual(binding.count, 45)
        let commit = Kmac.kmac256(key: mk, data: binding, customization: Array("monocles:omemo2:key-commitment:v3".utf8), outputLength: 64)
        XCTAssertEqual(hex(commit), "e04e685382db88563a43d2a5d55218bf917b5b57989b377636d88cf7f479bfc531b5a1a87a4eeef2909d8510a27f0b83e9f183361686ad5a3b00194794bde224")
        let derived = Kmac.kmac256(key: mk, data: binding, customization: Array("monocles:omemo2:payload:v3".utf8), outputLength: 44)
        XCTAssertEqual(hex(Array(derived[0..<32])), "91d133b399016d8ed75e9e585ecdcd7ffb1c95b9b364e188784ccbab610d97e7")
        XCTAssertEqual(hex(Array(derived[32...])), "058b5c01dd3d1eac0e564269")
    }

    // Proto-XEP §4.9.1: SHA3-512 del transcript del bundle (verifica anche SHA3 e la codifica).
    func testProtoXepBundleTranscriptDigest() {
        func u32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func lp(_ b: [UInt8]) -> [UInt8] { u32(b.count) + b }
        let ik: [UInt8] = [0x05] + [UInt8](repeating: 0x11, count: 32)
        let pqik = [UInt8](repeating: 0x22, count: 2592)
        let spk: [UInt8] = [0x05] + [UInt8](repeating: 0x33, count: 32)
        let kem = [UInt8](repeating: 0x44, count: 64)
        let t = Array("monocles:omemo2:pq-bundle:v4".utf8) + lp(Array("ML-DSA-87".utf8)) + lp(ik) + lp(pqik) + u32(7) + lp(spk) + lp(kem)
        XCTAssertEqual(hex(Kmac.sha3_512(t)), "51006cbeb032541274a0222b2b2e6ef68250803ccd9f8921ffcd8a93b4be7028dec4c46f0dfb1d50a3add5593871157dd0c1ce958d5aa35f320ffbdafcfd621a")
    }

    // Proto-XEP §4.6.3, tabella P(L).
    func testPadmeTable() {
        let table: [(Int, Int)] = [(0, 256), (255, 256), (256, 512), (1000, 1024), (4095, 4096), (4096, 4352),
                                   (5000, 5120), (10000, 10240), (65536, 67584), (100000, 100352), (1000000, 1015808)]
        for (l, p) in table { XCTAssertEqual(Omemo2Payload.paddedEnvelopeLength(l), p, "L=\(l)") }
    }

    func testEnvelopeRoundTrip() throws {
        let mk = Omemo2Payload.randomMessageKey()
        let binding = Omemo2Payload.contextBinding(from: "a@x.org", to: "b@x.org", sid: 1234)
        let env = Omemo2Payload.buildEnvelope(body: "Ciao <&> \"prova\" ✓", extraContentXML: [], from: "a@x.org", to: "b@x.org")
        XCTAssertEqual(env.count % 256, 0)
        let sealed = try Omemo2Payload.seal(envelope: env, messageKey: mk, binding: binding)
        let plain = try Omemo2Payload.open(payload: sealed.payload, commit: sealed.commit, messageKey: mk, binding: binding)
        let parsed = try Omemo2Payload.parseEnvelope(plain, expectedFrom: "a@x.org", expectedTo: "B@x.org/res", stanzaTime: nil)
        XCTAssertEqual(parsed.body, "Ciao <&> \"prova\" ✓")
        XCTAssertThrowsError(try Omemo2Payload.parseEnvelope(plain, expectedFrom: "c@x.org", expectedTo: "b@x.org", stanzaTime: nil))
        var badCommit = Array(sealed.commit); badCommit[0] ^= 1
        XCTAssertThrowsError(try Omemo2Payload.open(payload: sealed.payload, commit: Data(badCommit), messageKey: mk, binding: binding))
    }

    // Busta come la scrive la Velo Android (namespace espliciti, rpad, timestamp con nanosecondi).
    func testParseAndroidStyleEnvelope() throws {
        let xml = "<envelope xmlns=\"urn:xmpp:sce:1\"><content><body xmlns=\"jabber:client\">Ciao</body><active xmlns=\"http://jabber.org/protocol/chatstates\"/><store xmlns=\"urn:xmpp:hints\"/></content><time stamp=\"2026-11-17T08:25:36.119813030+00:00\"/><from jid=\"pixel@x.org\"/><to jid=\"veloios@x.org\"/><rpad>abc</rpad></envelope>"
        let date = Omemo2Payload.parseTimestamp("2026-11-17T08:25:36Z")!
        let parsed = try Omemo2Payload.parseEnvelope(Data(xml.utf8), expectedFrom: "pixel@x.org", expectedTo: "veloios@x.org", stanzaTime: date, now: date)
        XCTAssertEqual(parsed.body, "Ciao")
        XCTAssertEqual(parsed.otherElements.map { $0.name }, ["active"])
    }
}
