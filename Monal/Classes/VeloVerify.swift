//
//  VeloVerify.swift
//  Velo iOS — "Verifica contatto", come VeloVerifyActivity della Velo Android: i due telefoni
//  mostrano lo stesso codice (VeloSafetyCode), calcolato dai due account e dalle due impronte
//  ibride (chiave classica + chiave post-quantistica). Se coincide, in mezzo non c'è nessuno.
//  SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

struct VeloVerifyView: View {
    let contact: MLContact
    @State private var refresh = 0
    @State private var mismatch = false

    private struct Phone: Identifiable {
        let id: Int
        let fingerprint: String
        let code: String
    }

    private var account: xmpp? { contact.account }

    private func phones() -> [Phone]? {
        guard let account, let own = account.omemo.veloOwnHybridFingerprint() else { return nil }
        let ownJid = account.connectionProperties.identity.jid
        var result: [Phone] = []
        for (index, entry) in account.omemo.veloPeerHybridFingerprints(for: contact.contactJid).enumerated() {
            guard let fingerprint = entry["fingerprint"] as? String else { continue }
            let code = VeloPQBridge.safetyCode(ownJid: ownJid, ownKey: own, peerJid: contact.contactJid, peerKey: fingerprint)
            result.append(Phone(id: index, fingerprint: fingerprint, code: code))
        }
        return result
    }

    var body: some View {
        let _ = refresh
        let list = phones() ?? []
        Form {
            Section {
                Text("Leggi questo codice a \(contact.contactDisplayName), di persona o in chiamata. Se è uguale sui due telefoni, in mezzo non c'è nessuno.")
            }
            if list.isEmpty {
                Section {
                    Text("Le chiavi di questo contatto non sono ancora arrivate. Scambiatevi un messaggio, poi riapri questa pagina.")
                }
            }
            ForEach(list) { phone in
                Section(header: list.count > 1 ? Text("Suo telefono \(phone.id + 1)") : nil) {
                    Text(phone.code)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .textSelection(.enabled)
                    if VeloPQBridge.isVerified(account: contact.accountID, jid: contact.contactJid, hybrid: phone.fingerprint) {
                        Label("Verificato", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                    } else {
                        Button("I codici coincidono") {
                            VeloPQBridge.markVerified(account: contact.accountID, jid: contact.contactJid, hybrid: phone.fingerprint)
                            refresh += 1
                        }
                        Button("Non coincidono", role: .destructive) { mismatch = true }
                    }
                }
            }
            if let account, let own = account.omemo.veloOwnHybridFingerprint() {
                Section(header: Text("Impronte (per chi vuole confrontarle a mano)")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("La mia").font(.caption).foregroundColor(.secondary)
                        Text(VeloVerifyView.grouped(own)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }
                    ForEach(list) { phone in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.count > 1 ? "\(contact.contactDisplayName), telefono \(phone.id + 1)" : contact.contactDisplayName)
                                .font(.caption).foregroundColor(.secondary)
                            Text(VeloVerifyView.grouped(phone.fingerprint)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Verifica contatto")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Non coincidono", isPresented: $mismatch) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Non segnare questo contatto come verificato e non scrivere niente di delicato in questa chat. Se ha cambiato telefono, aspetta la chiave nuova e ricontrolla. Altrimenti qualcuno potrebbe ascoltare.")
        }
    }

    /// Gruppi di 8 caratteri, come l'Android ("9e2aa082 62208f60 …").
    static func grouped(_ hex: String) -> String {
        var out = ""
        for (i, ch) in hex.enumerated() {
            if i > 0 && i % 8 == 0 { out += " " }
            out.append(ch)
        }
        return out
    }
}
