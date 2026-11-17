// Velo iOS — wrapper Swift per le funzioni PQ del fork monocles di libsignal
// (rust/bridge/shared/src/protocol.rs: PqIdentityKeyPair_*, PqIdentity_*, PqBundle_*,
// PqAuth_*, PreKeyBundle_WithPqIdentity, KyberKeyPair_GenerateMlKem1024).
// Questo file viene copiato dalla CI dentro Sources/LibSignalClient, così usa gli helper
// interni del pacchetto (invokeFnReturning…, withAllBorrowed).
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SignalFfi

public enum VeloPQFFI {
    /// Coppia ML-DSA-87 serializzata (chiave di firma || chiave di verifica).
    public static func pqIdentityGenerate() throws -> Data {
        return try invokeFnReturningData {
            signal_pq_identity_key_pair_generate($0)
        }
    }

    public static func pqIdentityPublicKey(keyPair: Data) throws -> Data {
        return try keyPair.withUnsafeBorrowedBuffer { kp in
            try invokeFnReturningData {
                signal_pq_identity_key_pair_get_public_key($0, kp)
            }
        }
    }

    /// Firma ML-DSA-87 nel contesto "monocles:omemo2:pqid:v1" (fisso dentro libsignal).
    public static func pqSign(keyPair: Data, message: Data) throws -> Data {
        return try withAllBorrowed(.bytes(keyPair), .bytes(message)) { kp, msg in
            try invokeFnReturningData {
                signal_pq_identity_sign($0, kp, msg)
            }
        }
    }

    /// Digest KEM-BINDING: `oneTime` in ordine di documento del bundle.
    public static func kemBinding(kemSpkId: UInt32, kemSpk: Data, oneTime: [(id: UInt32, publicKey: Data)]) throws -> Data {
        var records = Data()
        for k in oneTime {
            records.append(contentsOf: be32(k.id))
            records.append(contentsOf: be32(UInt32(k.publicKey.count)))
            records.append(k.publicKey)
        }
        return try withAllBorrowed(.bytes(kemSpk), .bytes(records)) { spk, rec in
            try invokeFnReturningData {
                signal_pq_bundle_kem_binding($0, kemSpkId, spk, rec)
            }
        }
    }

    /// Transcript v4 del bundle (firmato da ML-DSA-87 e dall'identità classica).
    public static func bundleTranscript(identityKey: PublicKey, pqIdentityKey: Data, signedPreKeyId: UInt32,
                                        signedPreKey: PublicKey, kemBinding: Data) throws -> Data {
        return try withAllBorrowed(identityKey, signedPreKey, .bytes(pqIdentityKey), .bytes(kemBinding)) { ik, spk, pq, kb in
            try invokeFnReturningData {
                signal_pq_bundle_transcript($0, ik.const(), pq, signedPreKeyId, spk.const(), kb)
            }
        }
    }

    public static func bundleVerify(identityKey: PublicKey, pqIdentityKey: Data, pqSignature: Data, ikSignature: Data,
                                    signedPreKeyId: UInt32, signedPreKey: PublicKey, kemBinding: Data) throws -> Bool {
        return try withAllBorrowed(identityKey, signedPreKey, .bytes(pqIdentityKey), .bytes(pqSignature),
                                   .bytes(ikSignature), .bytes(kemBinding)) { ik, spk, pq, pqs, iks, kb in
            try invokeFnReturningBool {
                signal_pq_bundle_verify($0, ik.const(), pq, pqs, iks, signedPreKeyId, spk.const(), kb)
            }
        }
    }

    /// Voci kex per il transcript di <pq-auth>: JID (come scritto in <keys jid>, senza risorsa), rid, messaggio.
    public static func encodeKexEntries(_ entries: [(jid: String, rid: UInt32, message: Data)]) -> Data {
        var out = Data()
        for e in entries {
            let jid = Data(e.jid.utf8)
            out.append(contentsOf: be32(UInt32(jid.count)))
            out.append(jid)
            out.append(contentsOf: be32(e.rid))
            out.append(contentsOf: be32(UInt32(e.message.count)))
            out.append(e.message)
        }
        return out
    }

    public static func pqAuthTranscript(senderJid: String, senderDeviceId: UInt32, senderIdentityKey: PublicKey,
                                        senderPqIdentityKey: Data, entries: Data) throws -> Data {
        return try withAllBorrowed(senderIdentityKey, .bytes(senderPqIdentityKey), .bytes(entries)) { ik, pq, en in
            try invokeFnReturningData {
                signal_pq_auth_transcript($0, senderJid, senderDeviceId, ik.const(), pq, en)
            }
        }
    }

    public static func pqAuthVerify(senderJid: String, senderDeviceId: UInt32, senderIdentityKey: PublicKey,
                                    senderPqIdentityKey: Data, pqSignature: Data, ikSignature: Data,
                                    entries: Data) throws -> Bool {
        return try withAllBorrowed(senderIdentityKey, .bytes(senderPqIdentityKey), .bytes(pqSignature),
                                   .bytes(ikSignature), .bytes(entries)) { ik, pq, pqs, iks, en in
            try invokeFnReturningBool {
                signal_pq_auth_verify($0, senderJid, senderDeviceId, ik.const(), pq, pqs, iks, en)
            }
        }
    }

    public static func preKeyBundleWithPqIdentity(_ bundle: PreKeyBundle, pqIdentityKey: Data, pqSignature: Data,
                                                  ikSignature: Data, kemBinding: Data) throws -> PreKeyBundle {
        return try withAllBorrowed(bundle, .bytes(pqIdentityKey), .bytes(pqSignature), .bytes(ikSignature),
                                   .bytes(kemBinding)) { b, pq, pqs, iks, kb in
            try invokeFnReturningNativeHandle {
                signal_pre_key_bundle_with_pq_identity($0, b.const(), pq, pqs, iks, kb)
            }
        }
    }

    /// Coppia FIPS 203 ML-KEM-1024 (tag 0x0A), NON la Kyber Round 3 di KEMKeyPair.generate().
    public static func generateMlKem1024() -> KEMKeyPair {
        return failOnError {
            try invokeFnReturningNativeHandle {
                signal_kyber_key_pair_generate_ml_kem1024($0)
            }
        }
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        return [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }
}
