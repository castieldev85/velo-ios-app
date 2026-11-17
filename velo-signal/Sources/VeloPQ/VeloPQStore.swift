// Velo iOS — memoria persistente delle chiavi OMEMO2 PQ di un account (identità separata da
// quella legacy di Monal). Un file per record in Application Support/velo-pq/<account>/,
// protezione "complete until first user authentication".
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import LibSignalClient

public enum VeloPQStoreError: Error {
    case missing(String)
}

public final class VeloPQStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore, SessionStore {
    public let directory: URL
    private let ownJid: String
    private let lock = NSRecursiveLock()

    public private(set) var identityKeyPairValue: IdentityKeyPair
    public private(set) var registrationId: UInt32
    public private(set) var pqIdentityKeyPair: Data

    public init(accountKey: String, ownJid: String) throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let safe = accountKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "account"
        self.directory = base.appendingPathComponent("velo-pq", isDirectory: true).appendingPathComponent(safe, isDirectory: true)
        self.ownJid = ownJid.lowercased()
        for sub in ["", "prekeys", "signed", "kyber", "sessions", "identities", "pins", "kyber-used"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(sub, isDirectory: true),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        let fm = FileManager.default
        let idFile = directory.appendingPathComponent("identity")
        let regFile = directory.appendingPathComponent("registration-id")
        let pqFile = directory.appendingPathComponent("pq-identity")
        if let idData = fm.contents(atPath: idFile.path), let regData = fm.contents(atPath: regFile.path),
           let pqData = fm.contents(atPath: pqFile.path), regData.count == 4 {
            identityKeyPairValue = try IdentityKeyPair(bytes: idData)
            registrationId = regData.withUnsafeBytes { $0.load(as: UInt32.self) }
            pqIdentityKeyPair = pqData
        } else {
            identityKeyPairValue = IdentityKeyPair.generate()
            // Device id OMEMO2: 1…2^24-1 (limite del DeviceId del fork libsignal).
            registrationId = UInt32.random(in: 1...16_777_215)
            pqIdentityKeyPair = try VeloPQFFI.pqIdentityGenerate()
            try VeloPQStore.write(identityKeyPairValue.serialize(), to: idFile)
            var reg = registrationId
            try VeloPQStore.write(Data(bytes: &reg, count: 4), to: regFile)
            try VeloPQStore.write(pqIdentityKeyPair, to: pqFile)
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func file(_ sub: String, _ name: String) -> URL {
        return directory.appendingPathComponent(sub, isDirectory: true).appendingPathComponent(name)
    }

    private static func addressKey(_ address: ProtocolAddress) -> String {
        let name = address.name.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "x"
        return "\(name).\(address.deviceId)"
    }

    private func read(_ sub: String, _ name: String) -> Data? {
        return FileManager.default.contents(atPath: file(sub, name).path)
    }

    private func store(_ data: Data, _ sub: String, _ name: String) throws {
        try VeloPQStore.write(data, to: file(sub, name))
    }

    private func remove(_ sub: String, _ name: String) {
        try? FileManager.default.removeItem(at: file(sub, name))
    }

    private func list(_ sub: String) -> [String] {
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(sub).path)) ?? []
    }

    // MARK: IdentityKeyStore

    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair { identityKeyPairValue }
    public func localRegistrationId(context: StoreContext) throws -> UInt32 { registrationId }

    public func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
        lock.lock(); defer { lock.unlock() }
        let key = VeloPQStore.addressKey(address)
        let old = read("identities", key)
        try store(identity.serialize(), "identities", key)
        if let old = old, old != identity.serialize() { return .replacedExisting }
        return .newOrUnchanged
    }

    /// Come SQLiteAxolotlStore.isTrustedIdentity dell'Android: si fida di tutti tranne della propria
    /// chiave usata da un altro. La conferma dei dispositivi nuovi è un livello sopra (da portare).
    public func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction,
                                  context: StoreContext) throws -> Bool {
        if address.name.lowercased() == ownJid && address.deviceId == registrationId {
            return identity.serialize() == identityKeyPairValue.identityKey.serialize()
        }
        return true
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        guard let data = read("identities", VeloPQStore.addressKey(address)) else { return nil }
        return try IdentityKey(bytes: data)
    }

    // MARK: PreKeyStore

    public func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let data = read("prekeys", "\(id)") else { throw VeloPQStoreError.missing("prekey \(id)") }
        return try PreKeyRecord(bytes: data)
    }
    public func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        try store(record.serialize(), "prekeys", "\(id)")
    }
    public func removePreKey(id: UInt32, context: StoreContext) throws { remove("prekeys", "\(id)") }

    public func allPreKeyIds() -> [UInt32] { list("prekeys").compactMap { UInt32($0) }.sorted() }

    // MARK: SignedPreKeyStore

    public func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let data = read("signed", "\(id)") else { throw VeloPQStoreError.missing("signed prekey \(id)") }
        return try SignedPreKeyRecord(bytes: data)
    }
    public func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try store(record.serialize(), "signed", "\(id)")
    }
    public func latestSignedPreKey() throws -> SignedPreKeyRecord? {
        guard let id = list("signed").compactMap({ UInt32($0) }).max() else { return nil }
        return try loadSignedPreKey(id: id, context: NullContext())
    }

    // MARK: KyberPreKeyStore (i nomi "L<id>" sono le last-resort / kem-spk)

    public func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        if let data = read("kyber", "\(id)") ?? read("kyber", "L\(id)") {
            return try KyberPreKeyRecord(bytes: data)
        }
        throw VeloPQStoreError.missing("kyber prekey \(id)")
    }
    public func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try store(record.serialize(), "kyber", "\(id)")
    }
    public func storeLastResortKyberPreKey(_ record: KyberPreKeyRecord) throws {
        try store(record.serialize(), "kyber", "L\(record.id)")
    }
    /// Le one-time si cancellano dopo l'uso; per la last-resort si rifiuta la tupla ripetuta (§4.5.2).
    public func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {
        lock.lock(); defer { lock.unlock() }
        if read("kyber", "\(id)") != nil {
            remove("kyber", "\(id)")
            return
        }
        let tuple = "\(id)-\(signedPreKeyId)-" + baseKey.serialize().map { String(format: "%02x", $0) }.joined()
        if read("kyber-used", tuple) != nil {
            throw VeloPQStoreError.missing("reused last-resort KEM tuple")
        }
        try store(Data(), "kyber-used", tuple)
    }
    public func oneTimeKyberIds() -> [UInt32] {
        list("kyber").filter { !$0.hasPrefix("L") }.compactMap { UInt32($0) }.sorted()
    }
    public func latestLastResortKyber() throws -> KyberPreKeyRecord? {
        guard let id = list("kyber").filter({ $0.hasPrefix("L") }).compactMap({ UInt32($0.dropFirst()) }).max() else { return nil }
        return try loadKyberPreKey(id: id, context: NullContext())
    }
    public func maxKyberId() -> UInt32 {
        list("kyber").compactMap { UInt32($0.hasPrefix("L") ? String($0.dropFirst()) : $0) }.max() ?? 0
    }

    // MARK: SessionStore

    public func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        guard let data = read("sessions", VeloPQStore.addressKey(address)) else { return nil }
        return try SessionRecord(bytes: data)
    }
    public func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        return try addresses.map {
            guard let s = try loadSession(for: $0, context: context) else { throw VeloPQStoreError.missing("session \($0)") }
            return s
        }
    }
    public func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        try store(record.serialize(), "sessions", VeloPQStore.addressKey(address))
    }
    public func hasSession(name: String, deviceId: UInt32) -> Bool {
        guard let address = try? ProtocolAddress(name: name, deviceId: deviceId) else { return false }
        return read("sessions", VeloPQStore.addressKey(address)) != nil
    }

    // MARK: Pin dell'identità PQ su (JID nudo, impronta hex dell'IK a 33 byte)

    private static func pinName(_ jid: String, _ ikFingerprint: String) -> String {
        let s = jid.lowercased() + "|" + ikFingerprint.lowercased()
        return s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
    public func pinnedPqIdentity(jid: String, ikFingerprint: String) -> Data? {
        return read("pins", VeloPQStore.pinName(jid, ikFingerprint))
    }
    /// Scrive il pin se assente; restituisce quello in vigore dopo la chiamata (atomico sotto lock).
    public func pinIfAbsent(jid: String, ikFingerprint: String, pqIdentityKey: Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let existing = pinnedPqIdentity(jid: jid, ikFingerprint: ikFingerprint) { return existing }
        try store(pqIdentityKey, "pins", VeloPQStore.pinName(jid, ikFingerprint))
        return pqIdentityKey
    }

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
}

public struct NullContext: StoreContext {
    public init() {}
}
