// Velo iOS — ponte Objective-C ↔ motore OMEMO2 PQ (pacchetto VeloSignal, prodotto VeloPQ).
// Usato da MLOMEMO.m (sezione "VELO PQ") e da MLMessageProcessor.m / xmpp.m.
// SPDX-License-Identifier: AGPL-3.0-only

import CryptoKit
import Foundation
import VeloPQ

@objc public class VeloPQBridge: NSObject {
    private let engine: VeloPQEngine
    private let listsDir: URL
    private let queue = DispatchQueue(label: "velo.pq.lists")

    @objc public init?(accountKey: String, ownJid: String) {
        do {
            engine = try VeloPQEngine(accountKey: accountKey, ownJid: ownJid)
            listsDir = engine.store.directory.appendingPathComponent("device-lists", isDirectory: true)
            try FileManager.default.createDirectory(at: listsDir, withIntermediateDirectories: true)
        } catch {
            DDLogError("VELO PQ: inizializzazione fallita: \(error)")
            return nil
        }
        super.init()
        DDLogInfo("VELO PQ: device id \(engine.deviceId)")
    }

    @objc public static let namespace = VeloPQEngine.ns
    @objc public static let devicesNode = VeloPQEngine.ns + ":devices"
    @objc public static let bundlesNode = VeloPQEngine.ns + ":bundles"

    @objc public var deviceId: UInt32 { engine.deviceId }

    // MARK: Elenco dispositivi (salvato su disco per JID)

    private func listFile(_ jid: String) -> URL {
        let name = jid.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "x"
        return listsDir.appendingPathComponent(name)
    }

    @objc public func setDeviceList(_ ids: [NSNumber], forJid jid: String) {
        queue.sync {
            let text = ids.map { $0.stringValue }.joined(separator: ",")
            try? Data(text.utf8).write(to: listFile(jid), options: .atomic)
        }
    }

    /// nil = elenco PQ mai visto per quel JID (il contatto non usa la Velo PQ, o non l'abbiamo ancora chiesto).
    @objc public func deviceList(forJid jid: String) -> [NSNumber]? {
        return queue.sync {
            guard let data = try? Data(contentsOf: listFile(jid)) else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            if text.isEmpty { return [] }
            return text.split(separator: ",").compactMap { UInt32($0) }.map { NSNumber(value: $0) }
        }
    }

    /// Analizza un <item> del nodo devices (stringa XML) e restituisce gli id.
    @objc public static func parseDeviceList(_ itemXML: String) -> [NSNumber] {
        guard let root = try? VeloPQXML.parse(itemXML) else { return [] }
        let devices = root.name == "devices" ? root : root.firstChild(named: "devices")
        var out: [NSNumber] = []
        for d in devices?.children(named: "device") ?? [] {
            if let id = d.attrs["id"].flatMap(UInt32.init), id > 0, out.count < 128 { out.append(NSNumber(value: id)) }
        }
        return out
    }

    @objc public static func deviceListNode(_ ids: [NSNumber]) -> MLXMLNode? {
        return VeloPQXML.toNode(VeloPQEngine.deviceListXML(ids.map { $0.uint32Value }))
    }

    // MARK: Bundle e sessioni

    @objc public func bundleNode() -> MLXMLNode? {
        do {
            return VeloPQXML.toNode(try engine.bundleXML())
        } catch {
            DDLogError("VELO PQ: bundle non generato: \(error)")
            return nil
        }
    }

    @objc public func hasSession(jid: String, deviceId: UInt32) -> Bool {
        return engine.hasSession(jid: jid, deviceId: deviceId)
    }

    /// Restituisce nil se la sessione è stata costruita, altrimenti il motivo.
    @objc public func buildSession(jid: String, deviceId: UInt32, bundleXML: String) -> String? {
        do {
            try engine.buildSession(jid: jid, deviceId: deviceId, bundleXML: bundleXML)
            DDLogInfo("VELO PQ: sessione costruita con \(jid)/\(deviceId)")
            return nil
        } catch {
            DDLogError("VELO PQ: sessione con \(jid)/\(deviceId) rifiutata: \(error)")
            return "\(error)"
        }
    }

    /// Cifra per tutti i dispositivi noti di `toJid` e i nostri altri. Restituisce il nodo <encrypted>, o nil.
    @objc public func encryptedNode(body: String?, toJid: String, ownJid: String) -> MLXMLNode? {
        return encryptedNode(body: body, extraXML: [], toJid: toJid, ownJid: ownJid)
    }

    @objc public func encryptedNode(body: String?, extraXML: [String], toJid: String, ownJid: String) -> MLXMLNode? {
        var recipients: [String: [UInt32]] = [:]
        recipients[toJid.lowercased()] = (deviceList(forJid: toJid) ?? []).map { $0.uint32Value }
        if toJid.lowercased() != ownJid.lowercased() {
            recipients[ownJid.lowercased()] = (deviceList(forJid: ownJid) ?? []).map { $0.uint32Value }
        }
        do {
            let enc = try engine.encrypt(body: body, extraContentXML: extraXML, to: toJid, recipients: recipients)
            DDLogInfo("VELO PQ: messaggio cifrato per \(enc.remoteKeys) dispositivi di \(toJid)")
            return VeloPQXML.toNode(enc.xml)
        } catch {
            DDLogError("VELO PQ: cifratura verso \(toJid) fallita: \(error)")
            return nil
        }
    }

    /// Risultato: "body" (String, può mancare), "error" (String), "prekey" (Bool), "elements" ([String]).
    @objc public func decrypt(encryptedXML: String, senderJid: String, expectedTo: String,
                              stanzaTime: Date?) -> [String: Any] {
        do {
            guard let d = try engine.decrypt(encryptedXML: encryptedXML, senderJid: senderJid,
                                              expectedTo: expectedTo, stanzaTime: stanzaTime) else {
                return [:]
            }
            var out: [String: Any] = ["prekey": d.wasPreKey, "elements": d.otherElementNames]
            if let b = d.body { out["body"] = b }
            //VELO: nome, namespace e attributi di ogni elemento della busta (retract, ephemeral, purge, view-once...)
            var extras: [[String: Any]] = []
            for xml in d.contentChildrenXML {
                guard let node = try? VeloPQXML.parse(xml) else { continue }
                var texts: [String: String] = [:]
                for kid in node.kids where texts[kid.name] == nil { texts[kid.name] = kid.text }
                extras.append(["name": node.name, "ns": node.ns ?? "", "attrs": node.attrs, "texts": texts])
            }
            out["extras"] = extras
            //VELO: la Velo Android carica i file senza estensione e mette il tipo vero qui dentro
            for xml in d.contentChildrenXML {
                guard let node = try? VeloPQXML.parse(xml), node.name == "file-sharing",
                      let file = node.firstChild(named: "file") else { continue }
                if let type = file.firstChild(named: "media-type")?.text.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
                    out["mediaType"] = type
                }
                if let name = file.firstChild(named: "name")?.text, !name.isEmpty {
                    out["fileName"] = name
                }
                break
            }
            return out
        } catch {
            DDLogError("VELO PQ: decifratura da \(senderJid) fallita: \(error)")
            return ["error": "\(error)"]
        }
    }

    // MARK: Verifica del contatto (come VeloVerifyActivity / VeloSafetyCode della Velo Android)

    @objc public var ownHybridFingerprint: String? { engine.ownHybridFingerprint }

    @objc public func hybridFingerprint(jid: String, deviceId: UInt32) -> String? {
        return engine.hybridFingerprint(jid: jid, deviceId: deviceId)
    }

    /// Il codice che due persone si leggono: copre i due account e le due chiavi ibride, uguale sui due telefoni.
    @objc public static func safetyCode(ownJid: String, ownKey: String, peerJid: String, peerKey: String) -> String {
        let nl = "\n"
        let one = ownJid.lowercased() + nl + ownKey.lowercased()
        let two = peerJid.lowercased() + nl + peerKey.lowercased()
        let joined = one <= two ? one + nl + two : two + nl + one
        let digest = Array(SHA256.hash(data: Data(joined.utf8)))
        var code = ""
        for group in 0..<8 {
            var value = 0
            for i in 0..<3 { value = (value << 8) | Int(digest[group * 3 + i]) }
            if group > 0 { code += group == 4 ? nl : " " }
            code += String(format: "%05d", value % 100000)
        }
        return code
    }

    private static let verifiedKey = "veloPQVerified"

    @objc public static func isVerified(account: NSNumber, jid: String, hybrid: String) -> Bool {
        let all = HelperTools.defaultsDB().stringArray(forKey: verifiedKey) ?? []
        return all.contains("\(account.stringValue)|\(jid.lowercased())|\(hybrid.lowercased())")
    }

    @objc public static func markVerified(account: NSNumber, jid: String, hybrid: String) {
        var all = HelperTools.defaultsDB().stringArray(forKey: verifiedKey) ?? []
        let entry = "\(account.stringValue)|\(jid.lowercased())|\(hybrid.lowercased())"
        if !all.contains(entry) { all.append(entry) }
        HelperTools.defaultsDB().set(all, forKey: verifiedKey)
    }

    @objc public var needsRepublish: Bool {
        let r = engine.remainingOneTimeKeys
        return r.ec < 50 || r.kem < 50
    }
}

/// XML stringa → albero → MLXMLNode (il nodo radice porta il namespace, i figli lo ereditano).
enum VeloPQXML {
    final class Node {
        let name: String
        let ns: String?
        let attrs: [String: String]
        var text = ""
        var kids: [Node] = []
        init(name: String, ns: String?, attrs: [String: String]) { self.name = name; self.ns = ns; self.attrs = attrs }
        func firstChild(named n: String) -> Node? { kids.first { $0.name == n } }
        func children(named n: String) -> [Node] { kids.filter { $0.name == n } }
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let n = Node(name: elementName, ns: namespaceURI, attrs: attributeDict)
            if let top = stack.last { top.kids.append(n) } else { root = n }
            stack.append(n)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.removeLast()
        }
    }

    static func parse(_ xml: String) throws -> Node {
        let b = Builder()
        let p = XMLParser(data: Data(xml.utf8))
        p.shouldProcessNamespaces = true
        p.shouldResolveExternalEntities = false
        p.delegate = b
        guard p.parse(), let r = b.root else { throw NSError(domain: "VeloPQXML", code: 1) }
        return r
    }

    static func toNode(_ xml: String) -> MLXMLNode? {
        guard let root = try? parse(xml) else { return nil }
        return convert(root, parentNs: nil)
    }

    private static func convert(_ n: Node, parentNs: String?) -> MLXMLNode {
        let children = n.kids.map { convert($0, parentNs: n.ns) }
        let data: String? = n.kids.isEmpty && !n.text.isEmpty ? n.text : nil
        if let ns = n.ns, !ns.isEmpty, ns != parentNs {
            return MLXMLNode(element: n.name, andNamespace: ns, withAttributes: n.attrs, andChildren: children, andData: data)
        }
        return MLXMLNode(element: n.name, withAttributes: n.attrs, andChildren: children, andData: data)
    }
}

/// VELO: timer dei messaggi e visualizzazione singola, come la Velo Android.
/// Le scadenze sono per (account, contatto, id del messaggio); un timer le cancella appena scadono.
@objc public class VeloMessageRules: NSObject {
    private static let lock = NSLock()
    private static let expiryKey = "veloExpiry"
    private static let viewOnceKey = "veloViewOnce"
    private static let sweepQueue = DispatchQueue(label: "velo.expiry")
    private static var sweepTimer: DispatchSourceTimer?
    @objc public static let expiredNotification = "VeloMessageExpired"
    /// Scelte dell'orologio, come la Velo Android (0 = spento).
    @objc public static let timerChoices: [Int] = [0, 5, 10, 30, 60, 300, 3600, 86400]

    private static func key(_ account: NSNumber, _ buddy: String, _ messageId: String) -> String {
        return "\(account.stringValue)|\(buddy)|\(messageId)"
    }

    @objc public static func timerLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Spento"
        case ..<60: return "\(seconds) secondi"
        case 60: return "1 minuto"
        case ..<3600: return "\(seconds / 60) minuti"
        case 3600: return "1 ora"
        case ..<86400: return "\(seconds / 3600) ore"
        case 86400: return "1 giorno"
        default: return "\(seconds / 86400) giorni"
        }
    }

    @objc(sendTimerForAccount:jid:) public static func sendTimer(account: NSNumber, jid: String) -> Int {
        return HelperTools.defaultsDB().integer(forKey: "veloTimer.\(account.stringValue).\(jid)")
    }

    @objc(setSendTimer:forAccount:jid:) public static func setSendTimer(_ seconds: Int, account: NSNumber, jid: String) {
        let k = "veloTimer.\(account.stringValue).\(jid)"
        if seconds > 0 { HelperTools.defaultsDB().set(seconds, forKey: k) } else { HelperTools.defaultsDB().removeObject(forKey: k) }
    }

    @objc(registerExpiryForAccount:buddy:messageId:at:) public static func registerExpiry(account: NSNumber, buddy: String, messageId: String, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var d = (HelperTools.defaultsDB().dictionary(forKey: expiryKey) as? [String: Double]) ?? [:]
        d[key(account, buddy, messageId)] = date.timeIntervalSince1970
        HelperTools.defaultsDB().set(d, forKey: expiryKey)
    }

    @objc(registerViewOnceForAccount:buddy:messageId:seconds:) public static func registerViewOnce(account: NSNumber, buddy: String, messageId: String, seconds: Int) {
        lock.lock(); defer { lock.unlock() }
        var d = (HelperTools.defaultsDB().dictionary(forKey: viewOnceKey) as? [String: Int]) ?? [:]
        d[key(account, buddy, messageId)] = max(0, min(seconds, 60))
        HelperTools.defaultsDB().set(d, forKey: viewOnceKey)
    }

    /// nil se il messaggio non e' a visualizzazione singola, altrimenti i secondi (0 = finche' non lo chiudi).
    @objc(viewOnceSecondsForAccount:buddy:messageId:) public static func viewOnceSeconds(account: NSNumber, buddy: String, messageId: String) -> NSNumber? {
        lock.lock(); defer { lock.unlock() }
        let d = (HelperTools.defaultsDB().dictionary(forKey: viewOnceKey) as? [String: Int]) ?? [:]
        guard let s = d[key(account, buddy, messageId)] else { return nil }
        return NSNumber(value: s)
    }

    @objc(forgetViewOnceForAccount:buddy:messageId:) public static func forgetViewOnce(account: NSNumber, buddy: String, messageId: String) {
        lock.lock(); defer { lock.unlock() }
        var d = (HelperTools.defaultsDB().dictionary(forKey: viewOnceKey) as? [String: Int]) ?? [:]
        d.removeValue(forKey: key(account, buddy, messageId))
        HelperTools.defaultsDB().set(d, forKey: viewOnceKey)
    }

    @objc public static func startSweeper() {
        sweepQueue.async {
            guard sweepTimer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: sweepQueue)
            t.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
            t.setEventHandler { sweep() }
            t.resume()
            sweepTimer = t
        }
    }

    private static func sweep() {
        let now = Date().timeIntervalSince1970
        lock.lock()
        let due = ((HelperTools.defaultsDB().dictionary(forKey: expiryKey) as? [String: Double]) ?? [:]).filter { $0.value <= now }
        lock.unlock()
        guard !due.isEmpty else { return }
        var done: [String] = []
        for (k, at) in due {
            let parts = k.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let acc = Int(parts[0]) else { done.append(k); continue }
            if let hid = DataLayer.sharedInstance().veloExpireMessage(id: parts[2], buddy: parts[1], accountID: NSNumber(value: acc)) {
                DDLogInfo("VELO: messaggio a tempo scaduto e cancellato (history id \(hid))")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name(expiredNotification), object: nil, userInfo: ["historyId": hid])
                }
                done.append(k)
            } else if now - at > 120 {
                done.append(k)          //il messaggio non c'e' (mai salvato o gia' cancellato)
            }
        }
        lock.lock()
        var d = (HelperTools.defaultsDB().dictionary(forKey: expiryKey) as? [String: Double]) ?? [:]
        var v = (HelperTools.defaultsDB().dictionary(forKey: viewOnceKey) as? [String: Int]) ?? [:]
        var st = (HelperTools.defaultsDB().dictionary(forKey: storiesKey) as? [String: [String: Any]]) ?? [:]
        var seen = Set((HelperTools.defaultsDB().array(forKey: storiesSeenKey) as? [String]) ?? [])
        var storiesChanged = false
        for k in done {
            d.removeValue(forKey: k)
            v.removeValue(forKey: k)
            if st.removeValue(forKey: k) != nil { storiesChanged = true }
            seen.remove(k)
        }
        HelperTools.defaultsDB().set(d, forKey: expiryKey)
        HelperTools.defaultsDB().set(v, forKey: viewOnceKey)
        HelperTools.defaultsDB().set(st, forKey: storiesKey)
        HelperTools.defaultsDB().set(Array(seen), forKey: storiesSeenKey)
        lock.unlock()
        if storiesChanged { postStoriesChanged() }
    }

    // MARK: storie (urn:velo:story:0), come VeloStory della Velo Android

    private static let storiesKey = "veloStories"
    private static let storiesSeenKey = "veloStoriesSeen"
    @objc public static let storiesChangedNotification = "VeloStoriesChanged"
    private static var pendingStories: [String: (storyId: String, caption: String, expires: Date, at: Date)] = [:]

    public struct Story {
        public let key: String
        public let account: NSNumber
        public let buddy: String
        public let messageId: String
        public let storyId: String
        public let caption: String
        public let expires: Date
        public let inbound: Bool
        public let added: Date
    }

    private static func postStoriesChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name(storiesChangedNotification), object: nil)
        }
    }

    @objc(registerStoryForAccount:buddy:messageId:storyId:caption:expires:inbound:)
    public static func registerStory(account: NSNumber, buddy: String, messageId: String, storyId: String,
                                     caption: String?, expires: Date, inbound: Bool) {
        lock.lock()
        var d = (HelperTools.defaultsDB().dictionary(forKey: storiesKey) as? [String: [String: Any]]) ?? [:]
        d[key(account, buddy, messageId)] = [
            "id": storyId, "caption": caption ?? "", "expires": expires.timeIntervalSince1970,
            "inbound": inbound, "added": Date().timeIntervalSince1970,
        ]
        HelperTools.defaultsDB().set(d, forKey: storiesKey)
        lock.unlock()
        registerExpiry(account: account, buddy: buddy, messageId: messageId, at: expires)
        postStoriesChanged()
    }

    @objc(isStoryForAccount:buddy:messageId:)
    public static func isStory(account: NSNumber, buddy: String, messageId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let d = (HelperTools.defaultsDB().dictionary(forKey: storiesKey) as? [String: [String: Any]]) ?? [:]
        return d[key(account, buddy, messageId)] != nil
    }

    /// Le storie non ancora scadute (le nostre e quelle ricevute).
    public static func activeStories() -> [Story] {
        lock.lock()
        let d = (HelperTools.defaultsDB().dictionary(forKey: storiesKey) as? [String: [String: Any]]) ?? [:]
        lock.unlock()
        let now = Date().timeIntervalSince1970
        var result: [Story] = []
        for (k, v) in d {
            let parts = k.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let acc = Int(parts[0]),
                  let expires = v["expires"] as? Double, expires > now else { continue }
            result.append(Story(key: k, account: NSNumber(value: acc), buddy: parts[1], messageId: parts[2],
                                storyId: v["id"] as? String ?? parts[2], caption: v["caption"] as? String ?? "",
                                expires: Date(timeIntervalSince1970: expires), inbound: v["inbound"] as? Bool ?? true,
                                added: Date(timeIntervalSince1970: v["added"] as? Double ?? now)))
        }
        return result
    }

    public static func isStorySeen(_ storyKey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ((HelperTools.defaultsDB().array(forKey: storiesSeenKey) as? [String]) ?? []).contains(storyKey)
    }

    public static func markStorySeen(_ storyKey: String) {
        lock.lock()
        var seen = (HelperTools.defaultsDB().array(forKey: storiesSeenKey) as? [String]) ?? []
        if !seen.contains(storyKey) { seen.append(storyKey) }
        HelperTools.defaultsDB().set(seen, forKey: storiesSeenKey)
        lock.unlock()
    }

    /// Prima di mandare il file di una storia a un contatto: lo prende xmpp.sendMessage (entro 10 minuti).
    public static func setPendingStory(account: NSNumber, jid: String, storyId: String, caption: String, expires: Date) {
        lock.lock(); defer { lock.unlock() }
        pendingStories["\(account.stringValue)|\(jid)"] = (storyId, caption, expires, Date())
    }

    /// L'elemento <story/> per questo messaggio file, se ce n'è uno in attesa; la registra come nostra.
    @objc(takePendingStoryXMLForAccount:jid:messageId:)
    public static func takePendingStoryXML(account: NSNumber, jid: String, messageId: String) -> String? {
        lock.lock()
        let pending = pendingStories.removeValue(forKey: "\(account.stringValue)|\(jid)")
        lock.unlock()
        guard let pending, Date().timeIntervalSince(pending.at) < 600 else { return nil }
        func esc(_ s: String) -> String {
            return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let ms = Int64(pending.expires.timeIntervalSince1970 * 1000)
        var xml = "<story xmlns=\"urn:velo:story:0\" id=\"\(esc(pending.storyId))\" expires=\"\(ms)\">"
        if !pending.caption.isEmpty { xml += "<caption>\(esc(pending.caption))</caption>" }
        xml += "</story>"
        registerStory(account: account, buddy: jid, messageId: messageId, storyId: pending.storyId,
                      caption: pending.caption, expires: pending.expires, inbound: false)
        return xml
    }

    // MARK: cancellazione a distanza (urn:velo:remote-wipe:0), come RemoteWipe della Velo Android

    /// Quando l'account è comparso su questo telefono: un comando emesso prima non vale.
    @objc(markAccountAddedIfNeeded:) public static func markAccountAddedIfNeeded(_ account: NSNumber) {
        let k = "veloAccountAdded.\(account.stringValue)"
        if HelperTools.defaultsDB().object(forKey: k) == nil {
            HelperTools.defaultsDB().set(Int64(Date().timeIntervalSince1970 * 1000), forKey: k)
        }
    }

    @objc(wipeIssued:isForAccount:) public static func wipeIssued(_ issued: Int64, isForAccount account: NSNumber) -> Bool {
        let added = (HelperTools.defaultsDB().object(forKey: "veloAccountAdded.\(account.stringValue)") as? NSNumber)?.int64Value ?? 0
        return added == 0 || issued >= added
    }
}
