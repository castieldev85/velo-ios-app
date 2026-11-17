// Velo iOS — ponte Objective-C ↔ motore OMEMO2 PQ (pacchetto VeloSignal, prodotto VeloPQ).
// Usato da MLOMEMO.m (sezione "VELO PQ") e da MLMessageProcessor.m / xmpp.m.
// SPDX-License-Identifier: AGPL-3.0-only

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
        var recipients: [String: [UInt32]] = [:]
        recipients[toJid.lowercased()] = (deviceList(forJid: toJid) ?? []).map { $0.uint32Value }
        if toJid.lowercased() != ownJid.lowercased() {
            recipients[ownJid.lowercased()] = (deviceList(forJid: ownJid) ?? []).map { $0.uint32Value }
        }
        do {
            let enc = try engine.encrypt(body: body, to: toJid, recipients: recipients)
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
