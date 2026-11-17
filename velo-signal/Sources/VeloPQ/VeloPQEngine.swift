// Velo iOS — motore OMEMO2 PQ (urn:velo:omemo-pq:1), porta di AxolotlService/XmppOmemo2Message
// della Velo Android: bundle, sessioni PQXDH con identità ibrida, <pq-auth>, cifratura e decifratura.
// L'XMPP (pubsub, invio stanze) resta nel codice Objective-C di Monal (MLOMEMO.m, sezione VELO PQ).
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import LibSignalClient
import VeloPQCrypto

public enum VeloPQError: Error, CustomStringConvertible {
    case badBundle(String)
    case pqIdentityChanged(jid: String)
    case noSession(String)
    case notForThisDevice
    case handshake(String)
    case malformed(String)
    case nothingToEncryptFor

    public var description: String {
        switch self {
        case .badBundle(let s): return "bundle OMEMO2 non valido: \(s)"
        case .pqIdentityChanged(let j): return "identità post-quantistica di \(j) CAMBIATA: rifiutata"
        case .noSession(let s): return "nessuna sessione: \(s)"
        case .notForThisDevice: return "messaggio non cifrato per questo dispositivo"
        case .handshake(let s): return "handshake non autenticato: \(s)"
        case .malformed(let s): return "messaggio malformato: \(s)"
        case .nothingToEncryptFor: return "nessun dispositivo del destinatario"
        }
    }
}

public final class VeloPQEngine {
    public static let ns = "urn:velo:omemo-pq:1"
    static let numKeys = 100
    static let kemSpkRotation: TimeInterval = 30 * 24 * 60 * 60
    static let pqIdentityKeyLength = 2592
    static let pqSignatureLength = 4627
    static let ikSignatureLength = 64
    static let maxKeyCandidates = 8

    public let store: VeloPQStore
    public let ownJid: String
    private let ctx = NullContext()

    public init(accountKey: String, ownJid: String) throws {
        self.ownJid = ownJid.lowercased()
        self.store = try VeloPQStore(accountKey: accountKey, ownJid: ownJid)
    }

    public var deviceId: UInt32 { store.registrationId }

    private var ownAddress: ProtocolAddress {
        return try! ProtocolAddress(name: ownJid, deviceId: deviceId)
    }

    // MARK: - Bundle

    /// Prepara (genera/ruota) le chiavi e restituisce l'elemento <bundle> da pubblicare
    /// in urn:velo:omemo-pq:1:bundles, item id = deviceId.
    public func bundleXML() throws -> String {
        return try store.withLock {
            let identity = store.identityKeyPairValue
            let now = Date()
            // Signed prekey EC
            var spk = try store.latestSignedPreKey()
            if spk == nil || now.timeIntervalSince1970 * 1000 - Double(spk!.timestamp) > VeloPQEngine.kemSpkRotation * 1000 {
                let newId = (spk?.id ?? 0) + 1
                let priv = PrivateKey.generate()
                let sig = identity.privateKey.generateSignature(message: priv.publicKey.serialize())
                let record = try SignedPreKeyRecord(id: newId, timestamp: UInt64(now.timeIntervalSince1970 * 1000),
                                                    privateKey: priv, signature: sig)
                try store.storeSignedPreKey(record, id: newId, context: ctx)
                spk = record
            }
            let signed = spk!
            // Prekey EC one-time: rabbocco a 100
            var preKeyIds = store.allPreKeyIds()
            var nextPreKey = (preKeyIds.max() ?? 0) + 1
            while preKeyIds.count < VeloPQEngine.numKeys {
                let record = try PreKeyRecord(id: nextPreKey, privateKey: PrivateKey.generate())
                try store.storePreKey(record, id: nextPreKey, context: ctx)
                preKeyIds.append(nextPreKey)
                nextPreKey += 1
            }
            // KEM last-resort (kem-spk): riusata finché non ha 30 giorni
            var kemSpk = try store.latestLastResortKyber()
            if kemSpk == nil || now.timeIntervalSince1970 * 1000 - Double(kemSpk!.timestamp) > VeloPQEngine.kemSpkRotation * 1000 {
                kemSpk = try makeKyber(id: store.maxKyberId() + 1, identity: identity, now: now)
                try store.storeLastResortKyberPreKey(kemSpk!)
            }
            // KEM one-time: rabbocco a 100
            var kemIds = store.oneTimeKyberIds()
            while kemIds.count < VeloPQEngine.numKeys {
                let id = store.maxKyberId() + 1
                let record = try makeKyber(id: id, identity: identity, now: now)
                try store.storeKyberPreKey(record, id: id, context: ctx)
                kemIds.append(id)
            }
            let kemRecords = try kemIds.sorted().map { try store.loadKyberPreKey(id: $0, context: ctx) }
            // Firme dell'identità ibrida sul transcript v4
            let pqPublic = try VeloPQFFI.pqIdentityPublicKey(keyPair: store.pqIdentityKeyPair)
            let kemSpkPub = try kemSpk!.publicKey().serialize()
            let oneTime = try kemRecords.map { (id: $0.id, publicKey: try $0.publicKey().serialize()) }
            let kemBinding = try VeloPQFFI.kemBinding(kemSpkId: kemSpk!.id, kemSpk: kemSpkPub, oneTime: oneTime)
            let transcript = try VeloPQFFI.bundleTranscript(identityKey: identity.publicKey, pqIdentityKey: pqPublic,
                                                            signedPreKeyId: signed.id, signedPreKey: try signed.publicKey(),
                                                            kemBinding: kemBinding)
            let pqSig = try VeloPQFFI.pqSign(keyPair: store.pqIdentityKeyPair, message: transcript)
            let ikSig = identity.privateKey.generateSignature(message: transcript)

            var x = "<bundle xmlns=\"\(VeloPQEngine.ns)\" rev=\"4\">"
            x += "<spk id=\"\(signed.id)\">\(b64(try signed.publicKey().keyBytes))</spk>"
            x += "<spks>\(b64(signed.signature))</spks>"
            x += "<ik>\(b64(identity.publicKey.keyBytes))</ik>"
            x += "<prekeys>"
            for id in preKeyIds.sorted() {
                let r = try store.loadPreKey(id: id, context: ctx)
                x += "<pk id=\"\(id)\">\(b64(try r.publicKey().keyBytes))</pk>"
            }
            x += "</prekeys>"
            x += "<kem-spk id=\"\(kemSpk!.id)\">\(b64(kemSpkPub))</kem-spk>"
            x += "<kem-spks>\(b64(kemSpk!.signature))</kem-spks>"
            x += "<kem-prekeys>"
            for (i, r) in kemRecords.enumerated() {
                x += "<kem-pk id=\"\(r.id)\" sig=\"\(b64(r.signature))\">\(b64(oneTime[i].publicKey))</kem-pk>"
            }
            x += "</kem-prekeys>"
            x += "<pq-ik type=\"ML-DSA-87\">\(b64(pqPublic))</pq-ik>"
            x += "<pq-sig>\(b64(pqSig))</pq-sig>"
            x += "<ik-sig>\(b64(ikSig))</ik-sig>"
            x += "</bundle>"
            return x
        }
    }

    private func makeKyber(id: UInt32, identity: IdentityKeyPair, now: Date) throws -> KyberPreKeyRecord {
        let pair = VeloPQFFI.generateMlKem1024()
        let sig = identity.privateKey.generateSignature(message: pair.publicKey.serialize())
        return try KyberPreKeyRecord(id: id, timestamp: UInt64(now.timeIntervalSince1970 * 1000), keyPair: pair, signature: sig)
    }

    public static func deviceListXML(_ ids: [UInt32]) -> String {
        var x = "<devices xmlns=\"\(ns)\">"
        for id in Set(ids).sorted() { x += "<device id=\"\(id)\"/>" }
        return x + "</devices>"
    }

    // MARK: - Sessione in uscita dal bundle (buildSessionFromOmemo2PEP)

    public func hasSession(jid: String, deviceId: UInt32) -> Bool {
        return store.hasSession(name: jid.lowercased(), deviceId: deviceId)
    }

    public func buildSession(jid rawJid: String, deviceId: UInt32, bundleXML: String) throws {
        let jid = rawJid.lowercased()
        let b = try ParsedBundle(xml: bundleXML)
        guard !b.preKeys.isEmpty else { throw VeloPQError.badBundle("nessuna prekey EC one-time") }
        let pk = b.preKeys.randomElement()!
        let kem: (id: UInt32, key: Data, sig: Data)
        if let k = b.kemPreKeys.randomElement() { kem = k } else { kem = (b.kemSpkId, b.kemSpk, b.kemSpks) }
        let identity = try IdentityKey(bytes: b.ik)
        let ikFingerprint = identity.serialize().map { String(format: "%02x", $0) }.joined()
        let kemBinding = try VeloPQFFI.kemBinding(kemSpkId: b.kemSpkId, kemSpk: b.kemSpk,
                                                   oneTime: b.kemPreKeys.map { (id: $0.id, publicKey: $0.key) })
        let spkKey = try PublicKey(b.spk)
        guard try VeloPQFFI.bundleVerify(identityKey: identity.publicKey, pqIdentityKey: b.pqIk, pqSignature: b.pqSig,
                                         ikSignature: b.ikSig, signedPreKeyId: b.spkId, signedPreKey: spkKey,
                                         kemBinding: kemBinding) else {
            throw VeloPQError.badBundle("firme del transcript non valide")
        }
        if let pinned = store.pinnedPqIdentity(jid: jid, ikFingerprint: ikFingerprint), pinned != b.pqIk {
            throw VeloPQError.pqIdentityChanged(jid: jid)
        }
        guard try store.pinIfAbsent(jid: jid, ikFingerprint: ikFingerprint, pqIdentityKey: b.pqIk) == b.pqIk else {
            throw VeloPQError.pqIdentityChanged(jid: jid)
        }
        let plain = try PreKeyBundle(registrationId: 0, deviceId: deviceId, prekeyId: pk.id, prekey: try PublicKey(pk.key),
                                     signedPrekeyId: b.spkId, signedPrekey: spkKey, signedPrekeySignature: b.spks,
                                     identity: identity, kyberPrekeyId: kem.id, kyberPrekey: try KEMPublicKey(kem.key),
                                     kyberPrekeySignature: kem.sig)
        let full = try VeloPQFFI.preKeyBundleWithPqIdentity(plain, pqIdentityKey: b.pqIk, pqSignature: b.pqSig,
                                                            ikSignature: b.ikSig, kemBinding: kemBinding)
        let address = try ProtocolAddress(name: jid, deviceId: deviceId)
        try store.withLock {
            try processPreKeyBundle(full, for: address, ourAddress: ownAddress, sessionStore: store,
                                    identityStore: store, context: ctx)
        }
    }

    // MARK: - Cifratura (encryptOmemo2 + buildOmemo2Header + toElement)

    public struct Encrypted {
        public let xml: String
        public let remoteKeys: Int
    }

    /// `recipients`: JID nudo → device id (compresi i propri altri dispositivi). Se `body` è nil
    /// si manda una busta vuota (heal/heartbeat).
    public func encrypt(body: String?, extraContentXML: [String] = [], to rawTo: String,
                        recipients: [String: [UInt32]]) throws -> Encrypted {
        let to = rawTo.lowercased()
        let mk = Omemo2Payload.randomMessageKey()
        let binding = Omemo2Payload.contextBinding(from: ownJid, to: to, sid: deviceId)
        let envelope = Omemo2Payload.buildEnvelope(body: body, extraContentXML: extraContentXML, from: ownJid, to: to)
        let sealed = try Omemo2Payload.seal(envelope: envelope, messageKey: mk, binding: binding)
        var keys: [(jid: String, rid: UInt32, data: Data, kex: Bool)] = []
        var remote = 0
        try store.withLock {
            for (rawJid, devices) in recipients {
                let jid = rawJid.lowercased()
                for dev in devices.sorted() {
                    if jid == ownJid && dev == deviceId { continue }
                    guard store.hasSession(name: jid, deviceId: dev) else { continue }
                    let address = try ProtocolAddress(name: jid, deviceId: dev)
                    let msg = try signalEncrypt(message: Data(mk), for: address, localAddress: ownAddress,
                                                sessionStore: store, identityStore: store, context: ctx)
                    keys.append((jid, dev, msg.serialize(), msg.messageType == .preKey))
                    if jid != ownJid { remote += 1 }
                }
            }
        }
        guard remote > 0 || to == ownJid else { throw VeloPQError.nothingToEncryptFor }

        var header = "<header sid=\"\(deviceId)\">"
        let kex = keys.filter { $0.kex }
        if !kex.isEmpty {
            let pqPublic = try VeloPQFFI.pqIdentityPublicKey(keyPair: store.pqIdentityKeyPair)
            let entries = VeloPQFFI.encodeKexEntries(kex.map { (jid: $0.jid, rid: $0.rid, message: $0.data) })
            let transcript = try VeloPQFFI.pqAuthTranscript(senderJid: ownJid, senderDeviceId: deviceId,
                                                            senderIdentityKey: store.identityKeyPairValue.publicKey,
                                                            senderPqIdentityKey: pqPublic, entries: entries)
            let pqSig = try VeloPQFFI.pqSign(keyPair: store.pqIdentityKeyPair, message: transcript)
            let ikSig = store.identityKeyPairValue.privateKey.generateSignature(message: transcript)
            header += "<pq-auth><pq-ik type=\"ML-DSA-87\">\(b64(pqPublic))</pq-ik><pq-sig>\(b64(pqSig))</pq-sig><ik-sig>\(b64(ikSig))</ik-sig></pq-auth>"
        }
        let byJid = Dictionary(grouping: keys, by: { $0.jid })
        for jid in byJid.keys.sorted() {
            header += "<keys jid=\"\(jid)\">"
            for k in byJid[jid]! {
                header += "<key rid=\"\(k.rid)\"\(k.kex ? " kex=\"true\"" : "")>\(b64(k.data))</key>"
            }
            header += "</keys>"
        }
        header += "</header>"
        let xml = "<encrypted xmlns=\"\(VeloPQEngine.ns)\">\(header)<payload>\(b64(sealed.payload))</payload><commit>\(b64(sealed.commit))</commit></encrypted>"
        return Encrypted(xml: xml, remoteKeys: remote)
    }

    // MARK: - Decifratura (processReceivingOmemo2PayloadMessage + XmppOmemo2Message.decrypt)

    public struct Decrypted {
        public let body: String?
        public let contentChildrenXML: [String]
        public let otherElementNames: [String]
        public let senderDeviceId: UInt32
        public let wasPreKey: Bool
    }

    public func decrypt(encryptedXML: String, senderJid rawSender: String, expectedTo rawTo: String,
                        stanzaTime: Date?) throws -> Decrypted? {
        let sender = Omemo2PayloadParserHelpers.bare(rawSender).lowercased()
        let expectedTo = Omemo2PayloadParserHelpers.bare(rawTo).lowercased()
        let m = try ParsedEncrypted(xml: encryptedXML)
        guard let payload = m.payload else { return nil }
        let own = m.keys.filter { Omemo2PayloadParserHelpers.bare($0.jid).lowercased() == ownJid && $0.rid == deviceId }
        guard !own.isEmpty else { throw VeloPQError.notForThisDevice }
        let candidates = Array(own.prefix(VeloPQEngine.maxKeyCandidates))
        let address = try ProtocolAddress(name: sender, deviceId: m.sid)

        // <pq-auth> prima che libsignal veda un PreKeySignalMessage (§4.9.7)
        var senderIdentity: PublicKey?
        var hasKex = false
        for k in candidates where k.kex {
            guard let msg = try? PreKeySignalMessage(bytes: k.data) else { continue }
            hasKex = true
            let ik = msg.identityKey
            if let s = senderIdentity, s != ik { throw VeloPQError.handshake("chiavi d'identità diverse") }
            senderIdentity = ik
        }
        if hasKex, let ik = senderIdentity {
            guard let auth = m.pqAuth else { throw VeloPQError.handshake("manca <pq-auth>") }
            let entries = VeloPQFFI.encodeKexEntries(m.kexEntriesAsWritten.map { (jid: $0.jid, rid: $0.rid, message: $0.data) })
            let valid = (try? VeloPQFFI.pqAuthVerify(senderJid: sender, senderDeviceId: m.sid, senderIdentityKey: ik,
                                                     senderPqIdentityKey: auth.pqIk, pqSignature: auth.pqSig,
                                                     ikSignature: auth.ikSig, entries: entries)) ?? false
            guard valid else { throw VeloPQError.handshake("firma <pq-auth> non valida") }
            let fp = ik.serialize().map { String(format: "%02x", $0) }.joined()
            guard try store.pinIfAbsent(jid: sender, ikFingerprint: fp, pqIdentityKey: auth.pqIk) == auth.pqIk else {
                throw VeloPQError.pqIdentityChanged(jid: sender)
            }
        }

        var mk: Data?
        var wasPreKey = false
        var lastError: Error?
        try store.withLock {
            for k in candidates {
                do {
                    if k.kex {
                        let msg = try PreKeySignalMessage(bytes: k.data)
                        mk = try signalDecryptPreKey(message: msg, from: address, localAddress: ownAddress,
                                                     sessionStore: store, identityStore: store, preKeyStore: store,
                                                     signedPreKeyStore: store, kyberPreKeyStore: store, context: ctx)
                        wasPreKey = true
                    } else {
                        let msg = try SignalMessage(bytes: k.data)
                        mk = try signalDecrypt(message: msg, from: address, to: ownAddress, sessionStore: store,
                                               identityStore: store, context: ctx)
                    }
                    break
                } catch {
                    lastError = error
                }
            }
        }
        guard let messageKey = mk else { throw lastError ?? VeloPQError.noSession("\(address)") }
        let binding = Omemo2Payload.contextBinding(from: sender, to: expectedTo, sid: m.sid)
        let plain = try Omemo2Payload.open(payload: payload, commit: m.commit, messageKey: Array(messageKey), binding: binding)
        let env = try Omemo2Payload.parseEnvelope(plain, expectedFrom: sender, expectedTo: expectedTo, stanzaTime: stanzaTime)
        if wasPreKey {
            // Una prekey EC è stata consumata: il chiamante ripubblica il bundle.
        }
        return Decrypted(body: env.body, contentChildrenXML: env.contentChildrenXML,
                         otherElementNames: env.otherElements.map { $0.name }, senderDeviceId: m.sid, wasPreKey: wasPreKey)
    }

    /// Prekey rimaste (per sapere quando ripubblicare).
    public var remainingOneTimeKeys: (ec: Int, kem: Int) {
        return (store.allPreKeyIds().count, store.oneTimeKyberIds().count)
    }
}

func b64(_ d: Data) -> String { d.base64EncodedString() }

enum Omemo2PayloadParserHelpers {
    static func bare(_ jid: String) -> String {
        return jid.split(separator: "/", maxSplits: 1).first.map(String.init) ?? jid
    }
    static func decode(_ s: String) -> Data? {
        return Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: .ignoreUnknownCharacters)
    }
}

// MARK: - Parser XML (bundle e <encrypted>)

/// Albero XML minimo: nome, attributi, testo, figli.
final class XNode {
    let name: String
    let attrs: [String: String]
    var text = ""
    var children: [XNode] = []
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }
    func child(_ n: String) -> XNode? { children.first { $0.name == n } }
    func all(_ n: String) -> [XNode] { children.filter { $0.name == n } }

    static func parse(_ xml: String) throws -> XNode {
        let builder = XTreeBuilder()
        let p = XMLParser(data: Data(xml.utf8))
        p.shouldProcessNamespaces = true
        p.shouldResolveExternalEntities = false
        p.delegate = builder
        guard p.parse(), let root = builder.root else { throw VeloPQError.malformed("XML non valido") }
        return root
    }
}

private final class XTreeBuilder: NSObject, XMLParserDelegate {
    var root: XNode?
    var stack: [XNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let n = XNode(name: elementName, attrs: attributeDict)
        if let top = stack.last { top.children.append(n) } else { root = n }
        stack.append(n)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        stack.removeLast()
    }
}

struct ParsedBundle {
    let spkId: UInt32, spk: Data, spks: Data, ik: Data
    let preKeys: [(id: UInt32, key: Data)]
    let kemSpkId: UInt32, kemSpk: Data, kemSpks: Data
    let kemPreKeys: [(id: UInt32, key: Data, sig: Data)]
    let pqIk: Data, pqSig: Data, ikSig: Data

    /// Le chiavi EC dell'OMEMO2 sono 32 byte grezzi; libsignal vuole 0x05 davanti.
    static func ecKey(_ d: Data) throws -> Data {
        if d.count == 32 { return Data([0x05]) + d }
        if d.count == 33 && d.first == 0x05 { return d }
        throw VeloPQError.badBundle("chiave EC di lunghezza \(d.count)")
    }

    static func fixedType(_ n: XNode, _ alg: String) -> Bool {
        guard let t = n.attrs["type"] else { return true }
        return t == alg
    }

    static func isMlKem1024(_ d: Data) -> Bool { d.count == 1569 && d.first == 0x0A }

    init(xml: String) throws {
        var root = try XNode.parse(xml)
        if root.name == "item", let b = root.child("bundle") { root = b }
        guard root.name == "bundle" else { throw VeloPQError.badBundle("manca <bundle>") }
        func data(_ n: XNode?) throws -> Data {
            guard let n = n, let d = Omemo2PayloadParserHelpers.decode(n.text) else { throw VeloPQError.badBundle("campo mancante") }
            return d
        }
        func uid(_ n: XNode?) throws -> UInt32 {
            guard let s = n?.attrs["id"], let v = UInt32(s) else { throw VeloPQError.badBundle("id mancante") }
            return v
        }
        spkId = try uid(root.child("spk"))
        spk = try ParsedBundle.ecKey(try data(root.child("spk")))
        spks = try data(root.child("spks"))
        ik = try ParsedBundle.ecKey(try data(root.child("ik")))
        var pks: [(UInt32, Data)] = []
        for pk in root.child("prekeys")?.all("pk") ?? [] {
            if let id = pk.attrs["id"].flatMap(UInt32.init), let d = Omemo2PayloadParserHelpers.decode(pk.text),
               let k = try? ParsedBundle.ecKey(d) {
                pks.append((id, k))
            }
        }
        preKeys = pks.map { (id: $0.0, key: $0.1) }
        guard let kemSpkNode = root.child("kem-spk"), ParsedBundle.fixedType(kemSpkNode, "ML-KEM-1024") else {
            throw VeloPQError.badBundle("manca <kem-spk> utilizzabile")
        }
        kemSpkId = (try? uid(kemSpkNode)) ?? 0
        kemSpk = try data(kemSpkNode)
        guard ParsedBundle.isMlKem1024(kemSpk) else { throw VeloPQError.badBundle("<kem-spk> non ML-KEM-1024") }
        kemSpks = try data(root.child("kem-spks"))
        var kems: [(UInt32, Data, Data)] = []
        for k in root.child("kem-prekeys")?.all("kem-pk") ?? [] {
            guard ParsedBundle.fixedType(k, "ML-KEM-1024"),
                  let id = k.attrs["id"].flatMap(UInt32.init),
                  let d = Omemo2PayloadParserHelpers.decode(k.text), ParsedBundle.isMlKem1024(d) else { continue }
            let sig: Data
            if let s = k.attrs["sig"] {
                guard let decoded = Omemo2PayloadParserHelpers.decode(s) else { continue }
                sig = decoded
            } else {
                sig = Data()
            }
            kems.append((id, d, sig))
        }
        kemPreKeys = kems.map { (id: $0.0, key: $0.1, sig: $0.2) }
        guard let pqNode = root.child("pq-ik"), ParsedBundle.fixedType(pqNode, "ML-DSA-87") else {
            throw VeloPQError.badBundle("manca <pq-ik>")
        }
        pqIk = try data(pqNode)
        pqSig = try data(root.child("pq-sig"))
        guard root.child("ik-sig") != nil else { throw VeloPQError.badBundle("manca <ik-sig> (client da aggiornare)") }
        ikSig = try data(root.child("ik-sig"))
        guard pqIk.count == VeloPQEngine.pqIdentityKeyLength, pqSig.count == VeloPQEngine.pqSignatureLength,
              ikSig.count == VeloPQEngine.ikSignatureLength else {
            throw VeloPQError.badBundle("pq-ik/pq-sig/ik-sig di lunghezza sbagliata")
        }
    }
}

struct ParsedEncrypted {
    struct Key { let jid: String; let rid: UInt32; let data: Data; let kex: Bool }
    let sid: UInt32
    let keys: [Key]
    /// Ogni <key kex='true'> come scritto (jid senza risorsa, nessuna normalizzazione).
    let kexEntriesAsWritten: [Key]
    let payload: Data?
    let commit: Data?
    let pqAuth: (pqIk: Data, pqSig: Data, ikSig: Data)?

    init(xml: String) throws {
        let root = try XNode.parse(xml)
        guard root.name == "encrypted", let header = root.child("header") else { throw VeloPQError.malformed("manca <header>") }
        guard let sid = header.attrs["sid"].flatMap(UInt32.init), sid > 0 else { throw VeloPQError.malformed("sid") }
        self.sid = sid
        var keys: [Key] = []
        var kex: [Key] = []
        for block in header.all("keys") {
            guard let jidAttr = block.attrs["jid"] else { continue }
            let bare = Omemo2PayloadParserHelpers.bare(jidAttr)
            var count = 0
            for k in block.all("key") {
                guard let rid = k.attrs["rid"].flatMap(UInt32.init), let d = Omemo2PayloadParserHelpers.decode(k.text) else { continue }
                let isKex = k.attrs["kex"] == "true"
                if isKex { kex.append(Key(jid: bare, rid: rid, data: d, kex: true)) }
                if count < 128 { keys.append(Key(jid: bare, rid: rid, data: d, kex: isKex)) }
                count += 1
            }
        }
        self.keys = keys
        self.kexEntriesAsWritten = kex
        payload = root.child("payload").flatMap { Omemo2PayloadParserHelpers.decode($0.text) }
        commit = root.child("commit").flatMap { Omemo2PayloadParserHelpers.decode($0.text) }
        if let a = header.child("pq-auth"), let ikNode = a.child("pq-ik"), ParsedBundle.fixedType(ikNode, "ML-DSA-87"),
           let pq = Omemo2PayloadParserHelpers.decode(ikNode.text),
           let ps = a.child("pq-sig").flatMap({ Omemo2PayloadParserHelpers.decode($0.text) }),
           let isg = a.child("ik-sig").flatMap({ Omemo2PayloadParserHelpers.decode($0.text) }),
           pq.count == VeloPQEngine.pqIdentityKeyLength, ps.count == VeloPQEngine.pqSignatureLength,
           isg.count == VeloPQEngine.ikSignatureLength {
            pqAuth = (pq, ps, isg)
        } else {
            pqAuth = nil
        }
    }
}
