// Velo iOS — payload OMEMO2 PQ: binding di contesto, KMAC256, impegno sulla chiave,
// AES-256-GCM, busta SCE (XEP-0420) con padding Padmé.
// Porta 1:1 di XmppOmemo2Message.java della Velo Android (etichette "velo:", NON "monocles:").
// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Foundation

public enum Omemo2PayloadError: Error, CustomStringConvertible {
    case missingCommit
    case commitMismatch
    case badMessageKey
    case decryptFailed
    case envelope(String)

    public var description: String {
        switch self {
        case .missingCommit: return "OMEMO2 payload is missing its key commitment"
        case .commitMismatch: return "OMEMO2 key commitment mismatch"
        case .badMessageKey: return "OMEMO2 message key must be 32 bytes"
        case .decryptFailed: return "OMEMO2 payload authentication failed"
        case .envelope(let s): return "SCE envelope: \(s)"
        }
    }
}

public enum Omemo2Payload {
    public static let namespace = "urn:velo:omemo-pq:1"
    public static let messageKeyLength = 32
    static let ivLength = 12
    static let commitLength = 64
    // Etichette della Velo Android (XmppOmemo2Message.PAYLOAD_/COMMIT_CUSTOMIZATION).
    public static var payloadCustomization = Array("velo:omemo2:payload:v3".utf8)
    public static var commitCustomization = Array("velo:omemo2:key-commitment:v3".utf8)
    /// Finestra del controllo <time> (7 giorni), come MAX_TIME_SKEW_MS dell'Android.
    static let maxTimeSkew: TimeInterval = 7 * 24 * 60 * 60

    /// "OMEMO2" || 0x00 || from || 0x00 || to || 0x00 || u32be(sid) — JID nudi.
    public static func contextBinding(from: String, to: String, sid: UInt32) -> [UInt8] {
        var out = Array("OMEMO2".utf8)
        out.append(0)
        out += Array(from.utf8)
        out.append(0)
        out += Array(to.utf8)
        out.append(0)
        out += [UInt8(sid >> 24 & 0xFF), UInt8(sid >> 16 & 0xFF), UInt8(sid >> 8 & 0xFF), UInt8(sid & 0xFF)]
        return out
    }

    public static func derivePayloadKeys(messageKey: [UInt8], binding: [UInt8]) -> (key: [UInt8], iv: [UInt8]) {
        let derived = Kmac.kmac256(key: messageKey, data: binding, customization: payloadCustomization,
                                   outputLength: messageKeyLength + ivLength)
        return (Array(derived[0..<messageKeyLength]), Array(derived[messageKeyLength...]))
    }

    public static func keyCommitment(messageKey: [UInt8], binding: [UInt8]) -> [UInt8] {
        return Kmac.kmac256(key: messageKey, data: binding, customization: commitCustomization,
                            outputLength: commitLength)
    }

    public static func randomMessageKey() -> [UInt8] {
        var key = [UInt8](repeating: 0, count: messageKeyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, key.count, &key)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return key
    }

    /// Cifra la busta: restituisce payload (testo cifrato || tag) e commit.
    public static func seal(envelope: Data, messageKey: [UInt8], binding: [UInt8]) throws -> (payload: Data, commit: Data) {
        let keys = derivePayloadKeys(messageKey: messageKey, binding: binding)
        let box = try AES.GCM.seal(envelope, using: SymmetricKey(data: keys.key),
                                   nonce: try AES.GCM.Nonce(data: keys.iv), authenticating: Data(binding))
        let payload = box.ciphertext + box.tag
        return (payload, Data(keyCommitment(messageKey: messageKey, binding: binding)))
    }

    /// Verifica il commit (tempo costante) PRIMA di decifrare, poi apre il payload.
    public static func open(payload: Data, commit: Data?, messageKey: [UInt8], binding: [UInt8]) throws -> Data {
        guard messageKey.count == messageKeyLength else { throw Omemo2PayloadError.badMessageKey }
        guard let commit = commit else { throw Omemo2PayloadError.missingCommit }
        let expected = keyCommitment(messageKey: messageKey, binding: binding)
        guard constantTimeEqual(expected, Array(commit)) else { throw Omemo2PayloadError.commitMismatch }
        guard payload.count >= 16 else { throw Omemo2PayloadError.decryptFailed }
        let keys = derivePayloadKeys(messageKey: messageKey, binding: binding)
        do {
            let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: keys.iv),
                                            ciphertext: payload.prefix(payload.count - 16),
                                            tag: payload.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: keys.key), authenticating: Data(binding))
        } catch {
            throw Omemo2PayloadError.decryptFailed
        }
    }

    static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    // MARK: - Busta SCE

    /// Padmé(unpadded + 1) arrotondato a multipli di 256 (paddedEnvelopeLength dell'Android).
    public static func paddedEnvelopeLength(_ unpadded: Int) -> Int {
        let x = UInt64(unpadded + 1)
        let e = 63 - x.leadingZeroBitCount                     // floor(log2 x)
        let s = e == 0 ? 0 : (32 - UInt32(e).leadingZeroBitCount) // floor(log2 e) + 1
        let mask: UInt64 = (UInt64(1) << UInt64(e - s)) - 1
        let padme = (x + mask) & ~mask
        return Int(((padme + 255) / 256) * 256)
    }

    static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func isoTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: date)
    }

    private static let rpadAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

    /// Busta SCE con <body> (se c'è testo), elementi extra già serializzati, <time>, <from>, <to>, <rpad>.
    public static func buildEnvelope(body: String?, extraContentXML: [String], from: String, to: String,
                                     now: Date = Date()) -> Data {
        var content = ""
        if let body = body, !body.isEmpty {
            content += "<body xmlns=\"jabber:client\">\(xmlEscape(body))</body>"
        }
        for extra in extraContentXML { content += extra }
        let head = "<envelope xmlns=\"urn:xmpp:sce:1\"><content>\(content)</content>"
            + "<time stamp=\"\(isoTimestamp(now))\"/>"
            + "<from jid=\"\(xmlEscape(from))\"/>"
            + "<to jid=\"\(xmlEscape(to))\"/>"
        let tail = "</envelope>"
        let unpadded = head.utf8.count + "<rpad></rpad>".utf8.count + tail.utf8.count
        let target = paddedEnvelopeLength(unpadded)
        var rpad = [UInt8](repeating: 0, count: target - unpadded)
        var random = [UInt8](repeating: 0, count: rpad.count)
        _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        for i in 0..<rpad.count { rpad[i] = rpadAlphabet[Int(random[i]) % rpadAlphabet.count] }
        let envelope = head + "<rpad>" + String(decoding: rpad, as: UTF8.self) + "</rpad>" + tail
        return Data(envelope.utf8)
    }

    /// Contenuto decifrato di una busta SCE.
    public struct Envelope {
        public let body: String?
        /// Nomi locali (con namespace) degli altri elementi dentro <content>, per la diagnostica.
        public let otherElements: [(name: String, namespace: String?)]
        /// XML grezzo di ogni figlio di <content> esclusi i "server-processed elements".
        public let contentChildrenXML: [String]
    }

    /// Analizza la busta e applica i controlli obbligatori: <from>, <to>, <time> (±7 giorni
    /// rispetto all'ora della stanza, e mai oltre 7 giorni nel futuro).
    public static func parseEnvelope(_ plaintext: Data, expectedFrom: String, expectedTo: String,
                                     stanzaTime: Date?, now: Date = Date()) throws -> Envelope {
        let parser = EnvelopeParser(data: plaintext)
        guard parser.parse() else { throw Omemo2PayloadError.envelope("not well-formed XML") }
        guard parser.sawEnvelope else { throw Omemo2PayloadError.envelope("no <envelope>") }
        guard parser.sawContent else { throw Omemo2PayloadError.envelope("missing <content>") }
        guard let from = parser.fromJid else { throw Omemo2PayloadError.envelope("missing <from>") }
        guard bareLower(from) == bareLower(expectedFrom) else {
            throw Omemo2PayloadError.envelope("<from> mismatch")
        }
        guard let to = parser.toJid else { throw Omemo2PayloadError.envelope("missing <to>") }
        guard bareLower(to) == bareLower(expectedTo) else {
            throw Omemo2PayloadError.envelope("<to> mismatch")
        }
        guard let stamp = parser.timeStamp, let ts = parseTimestamp(stamp) else {
            throw Omemo2PayloadError.envelope("missing or unparseable <time>")
        }
        if ts.timeIntervalSince(now) > maxTimeSkew {
            throw Omemo2PayloadError.envelope("<time> too far in the future")
        }
        let reference = stanzaTime ?? now
        if abs(ts.timeIntervalSince(reference)) > maxTimeSkew {
            throw Omemo2PayloadError.envelope("<time> inconsistent with stanza time — possible replay")
        }
        return Envelope(body: parser.body, otherElements: parser.others, contentChildrenXML: parser.childrenXML)
    }

    static func bareLower(_ jid: String) -> String {
        let bare = jid.split(separator: "/", maxSplits: 1).first.map(String.init) ?? jid
        return bare.lowercased()
    }

    static func parseTimestamp(_ s: String) -> Date? {
        // XEP-0082: secondi obbligatori, frazione facoltativa, zona obbligatoria ('Z' o ±HH:MM).
        guard s.count >= 20 else { return nil }
        let chars = Array(s)
        guard chars[10] == "T" else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Frazioni oltre i millisecondi (es. nanosecondi del client desktop): tronca la frazione.
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            let trimmed = String(s[..<dot]) + String(s[end...])
            return f.date(from: trimmed)
        }
        return nil
    }
}

/// Parser minimo della busta SCE (Foundation XMLParser, niente entità esterne).
private final class EnvelopeParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    var sawEnvelope = false
    var sawContent = false
    var fromJid: String?
    var toJid: String?
    var timeStamp: String?
    var body: String?
    var others: [(name: String, namespace: String?)] = []
    var childrenXML: [String] = []

    private var depth = 0          // 1 = envelope, 2 = figli di envelope, 3 = figli di content
    private var inContent = false
    private var inBody = false
    private var bodyText = ""
    private var childBuffer = ""
    private var childDepth = 0
    private var skipChild = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
    }

    func parse() -> Bool { return parser.parse() }

    private static let serverProcessed: Set<String> = [
        "urn:xmpp:hints", "http://jabber.org/protocol/address",
    ]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1
        if depth == 1 {
            sawEnvelope = (elementName == "envelope")
            return
        }
        if depth == 2 {
            switch elementName {
            case "content": sawContent = true; inContent = true
            case "from": fromJid = attributeDict["jid"]
            case "to": toJid = attributeDict["jid"]
            case "time": timeStamp = attributeDict["stamp"]
            default: break
            }
            return
        }
        guard inContent else { return }
        if depth == 3 {
            let ns = namespaceURI
            let isServerProcessed = Self.serverProcessed.contains(ns ?? "")
                || (ns == "urn:xmpp:sid:0" && (elementName == "stanza-id" || elementName == "origin-id"))
                || (ns == "urn:xmpp:eme:0" && elementName == "encryption")
            skipChild = isServerProcessed
            childDepth = 0
            childBuffer = ""
            if elementName == "body" && !isServerProcessed {
                inBody = true
                bodyText = ""
            } else if !isServerProcessed {
                others.append((elementName, ns))
            }
        }
        if !skipChild {
            childDepth += 1
            var tag = "<\(elementName)"
            if childDepth == 1, let ns = namespaceURI, !ns.isEmpty {
                tag += " xmlns=\"\(Omemo2Payload.xmlEscape(ns))\""
            }
            for (k, v) in attributeDict.sorted(by: { $0.key < $1.key }) {
                tag += " \(k)=\"\(Omemo2Payload.xmlEscape(v))\""
            }
            tag += ">"
            childBuffer += tag
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inContent, depth >= 3 else { return }
        if inBody && depth == 3 { bodyText += string }
        if !skipChild { childBuffer += Omemo2Payload.xmlEscape(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if inContent && depth >= 3 {
            if !skipChild {
                childBuffer += "</\(elementName)>"
                childDepth -= 1
            }
            if depth == 3 {
                if inBody {
                    body = bodyText
                    inBody = false
                }
                if !skipChild { childrenXML.append(childBuffer) }
                skipChild = false
                childBuffer = ""
            }
        }
        if depth == 2 && elementName == "content" { inContent = false }
        depth -= 1
    }
}
