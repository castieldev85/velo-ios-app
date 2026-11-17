//
//  VeloTheme.swift
//  Velo iOS — temi in stile Telegram, gli stessi della Velo Android (VeloThemes.java):
//  11 temi pronti, notte automatica, "Personalizza" (colori, sfondo, forme, testo), "Il mio tema".
//  SPDX-License-Identifier: AGPL-3.0-only
//

import PhotosUI
import SwiftUI
import UIKit

// MARK: - Colori

struct VeloRGB: Equatable, Codable {
    var value: UInt32   // 0xRRGGBB

    init(_ value: UInt32) { self.value = value & 0xFFFFFF }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> UInt32 { UInt32(max(0, min(255, Int((x * 255).rounded())))) }
        value = (c(r) << 16) | (c(g) << 8) | c(b)
    }

    var r: Double { Double((value >> 16) & 0xFF) / 255 }
    var g: Double { Double((value >> 8) & 0xFF) / 255 }
    var b: Double { Double(value & 0xFF) / 255 }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(ui) }

    /// Luminanza relativa WCAG.
    var luminance: Double {
        func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }

    static func contrast(_ a: VeloRGB, _ b: VeloRGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static let darkText = VeloRGB(0x1B1B1F)
    static let lightText = VeloRGB(0xFFFFFF)

    /// Testo nero o bianco, quello che si legge meglio sopra questo colore.
    var onColor: VeloRGB {
        VeloRGB.contrast(.darkText, self) >= VeloRGB.contrast(.lightText, self) ? .darkText : .lightText
    }

    var isDark: Bool { onColor == .lightText }

    func blend(_ to: VeloRGB, _ amount: Double) -> VeloRGB {
        func mix(_ a: UInt32, _ b: UInt32) -> UInt32 { UInt32((Double(a) * (1 - amount) + Double(b) * amount).rounded()) }
        let r = mix((value >> 16) & 0xFF, (to.value >> 16) & 0xFF)
        let g = mix((value >> 8) & 0xFF, (to.value >> 8) & 0xFF)
        let b = mix(value & 0xFF, to.value & 0xFF)
        return VeloRGB((r << 16) | (g << 8) | b)
    }

    /// Questo colore, o la sfumatura più vicina verso nero o bianco che si legge su `background`.
    func readable(on background: VeloRGB, min: Double = 3.0) -> VeloRGB {
        if VeloRGB.contrast(self, background) >= min { return self }
        let target = background.onColor
        for step in 1...20 {
            let shade = blend(target, Double(step) / 20)
            if VeloRGB.contrast(shade, background) >= min { return shade }
        }
        return target
    }
}

// MARK: - Temi pronti (come la Velo Android)

struct VeloPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let dark: Bool
    let primary: VeloRGB
    let background: VeloRGB
    let bubbleOut: VeloRGB
    let bubbleIn: VeloRGB
    let chatBg: VeloRGB
    let accentPaintsBubble: Bool

    func sentColour(accent: VeloRGB?) -> VeloRGB { (accent != nil && accentPaintsBubble) ? accent! : bubbleOut }

    static let classico = VeloPreset(id: "classico", name: "Classico", dark: false, primary: VeloRGB(0x1F6FD6), background: VeloRGB(0xFFFFFF), bubbleOut: VeloRGB(0xD9F5C7), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xBFD8EE), accentPaintsBubble: false)
    static let giorno = VeloPreset(id: "giorno", name: "Giorno", dark: false, primary: VeloRGB(0x1F6FD6), background: VeloRGB(0xFFFFFF), bubbleOut: VeloRGB(0x1F6FD6), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xDDE4EE), accentPaintsBubble: true)
    static let notte = VeloPreset(id: "notte", name: "Notte", dark: true, primary: VeloRGB(0x7C8CFF), background: VeloRGB(0x141936), bubbleOut: VeloRGB(0x3A4596), bubbleIn: VeloRGB(0x1F2650), chatBg: VeloRGB(0x0D1126), accentPaintsBubble: true)
    static let nero = VeloPreset(id: "nero", name: "Nero", dark: true, primary: VeloRGB(0x4CC38A), background: VeloRGB(0x000000), bubbleOut: VeloRGB(0x2E6E4E), bubbleIn: VeloRGB(0x1C1C1E), chatBg: VeloRGB(0x000000), accentPaintsBubble: false)
    static let tramonto = VeloPreset(id: "tramonto", name: "Tramonto", dark: false, primary: VeloRGB(0xB84A33), background: VeloRGB(0xFFF8F3), bubbleOut: VeloRGB(0xFDE3CF), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xE6C0A6), accentPaintsBubble: false)
    static let oceano = VeloPreset(id: "oceano", name: "Oceano", dark: false, primary: VeloRGB(0x0B7A8A), background: VeloRGB(0xF4FAFB), bubbleOut: VeloRGB(0xD4F3F5), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xB9DCE1), accentPaintsBubble: false)
    static let lavanda = VeloPreset(id: "lavanda", name: "Lavanda", dark: false, primary: VeloRGB(0x6A4FC8), background: VeloRGB(0xFBF9FF), bubbleOut: VeloRGB(0xEAE3FF), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xD6CCF0), accentPaintsBubble: false)
    static let ciliegio = VeloPreset(id: "ciliegio", name: "Ciliegio", dark: false, primary: VeloRGB(0xC0306A), background: VeloRGB(0xFFF8FA), bubbleOut: VeloRGB(0xFDDDE9), bubbleIn: VeloRGB(0xFFFFFF), chatBg: VeloRGB(0xEBC3D3), accentPaintsBubble: false)
    static let foresta = VeloPreset(id: "foresta", name: "Foresta", dark: true, primary: VeloRGB(0x7DCB8A), background: VeloRGB(0x0F1A14), bubbleOut: VeloRGB(0x2E5E3E), bubbleIn: VeloRGB(0x1C2B22), chatBg: VeloRGB(0x0A130E), accentPaintsBubble: false)
    static let ambra = VeloPreset(id: "ambra", name: "Ambra", dark: true, primary: VeloRGB(0xF2B544), background: VeloRGB(0x16120B), bubbleOut: VeloRGB(0x5C4416), bubbleIn: VeloRGB(0x2A231A), chatBg: VeloRGB(0x0F0C07), accentPaintsBubble: false)
    static let aurora = VeloPreset(id: "aurora", name: "Aurora", dark: true, primary: VeloRGB(0x5EE0C8), background: VeloRGB(0x0B1120), bubbleOut: VeloRGB(0x1D4A5A), bubbleIn: VeloRGB(0x1A2236), chatBg: VeloRGB(0x070B16), accentPaintsBubble: false)

    static let all: [VeloPreset] = [classico, giorno, notte, nero, tramonto, oceano, lavanda, ciliegio, foresta, ambra, aurora]

    static func byId(_ id: String?) -> VeloPreset { all.first { $0.id == id } ?? classico }
}

/// I 40 colori pronti di "Personalizza" (gli stessi della Velo Android).
let veloSwatches: [UInt32] = [
    0xFFFFFF, 0xF1F4F9, 0xCBD5E1, 0x64748B, 0x334155, 0x16233A, 0x0B1220, 0x000000,
    0xFDE2E4, 0xF9A8B8, 0xEF4444, 0xB91C1C, 0xFFE3C2, 0xFDBA74, 0xEA7A1F, 0xB4530E,
    0xFFF3B0, 0xFACC15, 0xCA8A04, 0x7A5B05, 0xD9F5C7, 0x86EFAC, 0x16A34A, 0x14532D,
    0xCCFBF1, 0x2DD4BF, 0x0E8078, 0x134E4A, 0xBFD8EE, 0x60A5FA, 0x1F6FD6, 0x1E3A8A,
    0xE0D7FF, 0xA78BFA, 0x7E48CC, 0x4C1D95, 0xFBCFE8, 0xF472B6, 0xBF3B78, 0x831843,
]

// MARK: - Sfondi della chat (gli stessi disegni della Velo Android, tessera di 86 punti)

struct VeloWallpaper: Identifiable {
    let id: String
    let name: String
    let path: String
    let width: CGFloat

    static let plain = "plain"
    static let gradient = "gradient"
    static let glow = "glow"
    static let photo = "photo"

    static let drawings: [VeloWallpaper] = [
        VeloWallpaper(id: "drawings", name: "Disegni", path: "M10 14h16a5 5 0 0 1 5 5v8a5 5 0 0 1-5 5H17l-6 5 1-5a5 5 0 0 1-5-5v-8a5 5 0 0 1 3-5ZM54 22a8 8 0 1 0 16 0 8 8 0 1 0-16 0M56 62l8-12 8 12M60 58h8M20 58l3 7 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z", width: 2),
        VeloWallpaper(id: "dots", name: "Puntini", path: "M20 20h.01M63 20h.01M41 63h.01M84 63h.01M0 63h.01", width: 5),
        VeloWallpaper(id: "waves", name: "Onde", path: "M0 20c14-12 29-12 43 0s29 12 43 0M0 63c14-12 29-12 43 0s29 12 43 0", width: 2.5),
        VeloWallpaper(id: "stars", name: "Stelle", path: "M18 8v14M11 15h14M64 54v10M59 59h10M66 22a9 9 0 1 0 9 12a7 7 0 1 1-9-12ZM44 20h.01M8 44h.01M30 40h.01M12 66h.01M36 76h.01M78 80h.01M50 36h.01", width: 2.2),
        VeloWallpaper(id: "hearts", name: "Cuori", path: "M22 26c-4-6-14-4-12 4 2 6 12 12 12 12s10-6 12-12c2-8-8-10-12-4ZM62 60c-3-4.5-10.5-3-9 3 1.5 4.5 9 9 9 9s7.5-4.5 9-9c1.5-6-6-7.5-9-3Z", width: 2),
        VeloWallpaper(id: "leaves", name: "Foglie", path: "M12 40c0-14 12-26 28-26 0 16-12 26-28 26ZM12 40l20-18M48 78c4-13 17-20 30-16-4 13-17 20-30 16ZM48 78l22-11", width: 2),
        VeloWallpaper(id: "space", name: "Spazio", path: "M21 30a9 9 0 1 0 18 0a9 9 0 1 0-18 0M14 36c8 4 26 0 32-9M64 58l2 5 5 2-5 2-2 5-2-5-5-2 5-2ZM66 16h.01M78 38h.01M10 70h.01M40 76h.01", width: 2),
        VeloWallpaper(id: "music", name: "Musica", path: "M20 40V18l14-4v22M20 40a4 3 0 1 1-8 0a4 3 0 1 1 8 0M34 36a4 3 0 1 1-8 0a4 3 0 1 1 8 0M66 72V52l9 5M66 72a4 3 0 1 1-8 0a4 3 0 1 1 8 0", width: 2),
        VeloWallpaper(id: "bubbles", name: "Bolle", path: "M10 24a10 10 0 1 0 20 0a10 10 0 1 0-20 0M57 18a5 5 0 1 0 10 0a5 5 0 1 0-10 0M44 60a14 14 0 1 0 28 0a14 14 0 1 0-28 0M12 70a4 4 0 1 0 8 0a4 4 0 1 0-8 0", width: 1.8),
        VeloWallpaper(id: "rhombs", name: "Rombi", path: "M0 43L43 0L86 43L43 86Z", width: 1.6),
        VeloWallpaper(id: "zigzag", name: "Zig-zag", path: "M0 22l10.75-8 10.75 8 10.75-8 10.75 8 10.75-8 10.75 8 10.75-8 10.75 8M0 65l10.75-8 10.75 8 10.75-8 10.75 8 10.75-8 10.75 8 10.75-8 10.75 8", width: 2.2),
        VeloWallpaper(id: "notebook", name: "Quaderno", path: "M0 .5H86M0 22H86M0 43.5H86M0 65H86M.5 0V86M22 0V86M43.5 0V86M65 0V86", width: 1),
    ]

    static func byId(_ id: String) -> VeloWallpaper? { drawings.first { $0.id == id } }
}

/// Lettore minimo dei percorsi SVG (M L H V C S A Z, maiuscole e minuscole) per i disegni degli sfondi.
enum VeloSVGPath {
    static func parse(_ d: String) -> UIBezierPath {
        let path = UIBezierPath()
        var tokens: [String] = []
        var current = ""
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" {
                if !current.isEmpty && current.last != "e" { tokens.append(current); current = "" }
                current.append(ch)
            } else if ch == "." {
                if current.contains(".") { tokens.append(current); current = "" }
                current.append(ch)
            } else {
                current.append(ch)
            }
            i += 1
        }
        if !current.isEmpty { tokens.append(current) }

        var idx = 0
        var cmd: Character = "M"
        var pt = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl: CGPoint? = nil
        func num() -> CGFloat? {
            guard idx < tokens.count, let v = Double(tokens[idx]) else { return nil }
            idx += 1
            return CGFloat(v)
        }
        func flag() -> Bool {
            // le bandiere degli archi possono essere attaccate ("0 1 0" o "01")
            guard idx < tokens.count else { return false }
            let t = tokens[idx]
            if t.count > 1, let first = t.first, first == "0" || first == "1" {
                tokens[idx] = String(t.dropFirst())
                return first == "1"
            }
            idx += 1
            return t == "1"
        }
        while idx < tokens.count {
            if let c = tokens[idx].first, c.isLetter, tokens[idx].count == 1 {
                cmd = c
                idx += 1
                if cmd == "Z" || cmd == "z" {
                    path.close()
                    pt = start
                    lastCtrl = nil
                    continue
                }
            }
            let rel = cmd.isLowercase
            let base = rel ? pt : .zero
            switch cmd.uppercased().first! {
            case "M":
                guard let x = num(), let y = num() else { idx += 1; continue }
                pt = CGPoint(x: base.x + x, y: base.y + y)
                path.move(to: pt)
                start = pt
                cmd = rel ? "l" : "L"
                lastCtrl = nil
            case "L":
                guard let x = num(), let y = num() else { idx += 1; continue }
                pt = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: pt)
                lastCtrl = nil
            case "H":
                guard let x = num() else { idx += 1; continue }
                pt = CGPoint(x: rel ? pt.x + x : x, y: pt.y)
                path.addLine(to: pt)
                lastCtrl = nil
            case "V":
                guard let y = num() else { idx += 1; continue }
                pt = CGPoint(x: pt.x, y: rel ? pt.y + y : y)
                path.addLine(to: pt)
                lastCtrl = nil
            case "C":
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(), let x = num(), let y = num() else { idx += 1; continue }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                pt = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: pt, controlPoint1: c1, controlPoint2: c2)
                lastCtrl = c2
            case "S":
                guard let x2 = num(), let y2 = num(), let x = num(), let y = num() else { idx += 1; continue }
                let c1 = lastCtrl.map { CGPoint(x: 2 * pt.x - $0.x, y: 2 * pt.y - $0.y) } ?? pt
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                pt = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: pt, controlPoint1: c1, controlPoint2: c2)
                lastCtrl = c2
            case "A":
                guard let rx = num(), let ry = num(), let rot = num() else { idx += 1; continue }
                let large = flag()
                let sweep = flag()
                guard let x = num(), let y = num() else { continue }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                addArc(path, from: pt, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                pt = end
                lastCtrl = nil
            default:
                idx += 1
            }
        }
        return path
    }

    /// Arco ellittico SVG, approssimato con segmenti (per tessere di 86 punti basta e avanza).
    private static func addArc(_ path: UIBezierPath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let t1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dt = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi }
        if sweep && dt < 0 { dt += 2 * .pi }
        let steps = max(8, Int(abs(dt) / (.pi / 16)))
        for s in 1...steps {
            let t = t1 + dt * CGFloat(s) / CGFloat(steps)
            let x = cx + rx * cos(t) * cosP - ry * sin(t) * sinP
            let y = cy + rx * cos(t) * sinP + ry * sin(t) * cosP
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
}

// MARK: - Il tema attivo

@objc final class VeloTheme: NSObject {
    static let changedNotification = Notification.Name("VeloThemeChanged")

    private static var d: UserDefaults { UserDefaults.standard }

    // chiavi (UserDefaults.standard: le legge anche la libreria della chat, vedi build-ios.yml)
    static let kPreset = "veloThemePreset"
    static let kAccent = "veloThemeAccent"
    static let kAutoNight = "veloAutoNight"
    static let kHandMade = "veloThemeHandMade"
    static let kColours = "veloThemeColours"
    static let kPattern = "veloChatPattern"
    static let kCorners = "veloBubbleCorners"
    static let kTextSize = "veloTextSize"
    static let kFont = "veloFontDesign"
    static let kAvatar = "veloAvatarShape"
    static let kListLines = "veloListLines"
    static let kSaved = "veloSavedTheme"

    /// I sei colori di "Personalizza".
    struct Colours: Codable, Equatable {
        var bar: VeloRGB
        var buttons: VeloRGB
        var sent: VeloRGB
        var received: VeloRGB
        var wall: VeloRGB
        var page: VeloRGB
    }

    /// Tutto quello che serve per disegnare l'app.
    struct Palette: Equatable {
        var dark: Bool
        var bar: VeloRGB
        var tint: VeloRGB
        var page: VeloRGB
        var sent: VeloRGB
        var received: VeloRGB
        var wall: VeloRGB

        var onBar: VeloRGB { bar.onColor }
        var onSent: VeloRGB { sent.onColor }
        var onReceived: VeloRGB { received.onColor }
        /// I pulsanti sono anche parole sulla pagina: devono leggersi (come VeloThemes.fixContrast).
        var tintOnPage: VeloRGB { tint.readable(on: page) }
    }

    static var preset: VeloPreset { VeloPreset.byId(d.string(forKey: kPreset)) }
    static var accent: VeloRGB? { (d.object(forKey: kAccent) as? Int).map { VeloRGB(UInt32($0)) } }
    static var autoNight: Bool { d.bool(forKey: kAutoNight) }
    static var handMade: Bool { d.bool(forKey: kHandMade) }
    static var pattern: String { d.string(forKey: kPattern) ?? "drawings" }
    static var corners: Int { (d.object(forKey: kCorners) as? Int) ?? 18 }
    static var textSize: Int { (d.object(forKey: kTextSize) as? Int) ?? 15 }
    static var fontDesign: String { d.string(forKey: kFont) ?? "modern" }
    static var avatarShape: String { d.string(forKey: kAvatar) ?? "round" }
    static var listLines: Int { (d.object(forKey: kListLines) as? Int) ?? 2 }

    static var colours: Colours? {
        guard let data = d.data(forKey: kColours) else { return nil }
        return try? JSONDecoder().decode(Colours.self, from: data)
    }

    static func colours(of preset: VeloPreset, accent: VeloRGB?) -> Colours {
        let primary = accent ?? preset.primary
        return Colours(bar: preset.dark ? preset.background.blend(.lightText, 0.06) : primary, buttons: primary,
                       sent: preset.sentColour(accent: accent), received: preset.bubbleIn, wall: preset.chatBg,
                       page: preset.background)
    }

    /// La tavolozza attiva; con la notte automatica un tema chiaro si accoppia a Notte, uno scuro a Classico.
    static func palette(systemDark: Bool) -> Palette {
        if handMade, let c = colours {
            return Palette(dark: c.page.isDark, bar: c.bar, tint: c.buttons, page: c.page, sent: c.sent, received: c.received, wall: c.wall)
        }
        var p = preset
        var a = accent
        if autoNight {
            if systemDark && !p.dark { p = .notte; a = nil }
            if !systemDark && p.dark { p = .classico; a = nil }
        }
        let c = colours(of: p, accent: a)
        return Palette(dark: p.dark, bar: c.bar, tint: c.buttons, page: c.page, sent: c.sent, received: c.received, wall: c.wall)
    }

    static var current: Palette {
        let dark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        return palette(systemDark: dark)
    }

    // MARK: Scelte

    static func choose(preset: VeloPreset, accent: VeloRGB?, autoNight: Bool) {
        d.set(preset.id, forKey: kPreset)
        if let accent { d.set(Int(accent.value), forKey: kAccent) } else { d.removeObject(forKey: kAccent) }
        d.set(autoNight, forKey: kAutoNight)
        d.set(false, forKey: kHandMade)
        apply()
    }

    static func setAutoNight(_ on: Bool) {
        d.set(on, forKey: kAutoNight)
        apply()
    }

    static func setColours(_ c: Colours) {
        if let data = try? JSONEncoder().encode(c) { d.set(data, forKey: kColours) }
        d.set(true, forKey: kHandMade)
        apply()
    }

    static func set(_ value: Any?, forKey key: String) {
        if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        apply()
    }

    static func reset() {
        for k in [kPreset, kAccent, kAutoNight, kHandMade, kColours, kPattern, kCorners, kTextSize, kFont, kAvatar, kListLines] {
            d.removeObject(forKey: k)
        }
        MLImageManager.sharedInstance().saveBackgroundImageData(nil, for: nil)
        apply()
    }

    /// "Salva come il mio tema": colori, sfondo, forme e testo insieme.
    static func saveMine() {
        let p = current
        let c = Colours(bar: p.bar, buttons: p.tint, sent: p.sent, received: p.received, wall: p.wall, page: p.page)
        var saved: [String: Any] = [kPattern: pattern, kCorners: corners, kTextSize: textSize, kFont: fontDesign, kAvatar: avatarShape]
        if let data = try? JSONEncoder().encode(c) { saved[kColours] = data }
        d.set(saved, forKey: kSaved)
    }

    static var hasSaved: Bool { d.dictionary(forKey: kSaved) != nil }

    static func loadMine() {
        guard let saved = d.dictionary(forKey: kSaved) else { return }
        for (k, v) in saved { d.set(v, forKey: k) }
        d.set(true, forKey: kHandMade)
        apply()
    }

    // MARK: Applicazione a tutta l'app

    @objc static func apply() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        let systemDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        let p = palette(systemDark: systemDark)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = p.bar.ui
        bar.shadowColor = .clear
        bar.titleTextAttributes = [.foregroundColor: p.onBar.ui]
        bar.largeTitleTextAttributes = [.foregroundColor: p.onBar.ui]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.foregroundColor: p.onBar.ui]
        bar.buttonAppearance = button
        bar.doneButtonAppearance = button
        bar.backButtonAppearance = button

        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = bar
        proxy.scrollEdgeAppearance = bar
        proxy.compactAppearance = bar
        proxy.tintColor = p.onBar.ui

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = p.page.ui
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = p.tintOnPage.ui

        UISwitch.appearance().onTintColor = p.tintOnPage.ui

        for window in windows {
            window.overrideUserInterfaceStyle = (autoNight && !handMade) ? .unspecified : (p.dark ? .dark : .light)
            window.tintColor = p.tintOnPage.ui
            window.backgroundColor = p.page.ui
            if let root = window.rootViewController { restyle(root, bar: bar, tint: p.onBar.ui) }
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static func restyle(_ vc: UIViewController, bar: UINavigationBarAppearance, tint: UIColor) {
        if let nav = vc as? UINavigationController {
            nav.navigationBar.standardAppearance = bar
            nav.navigationBar.scrollEdgeAppearance = bar
            nav.navigationBar.compactAppearance = bar
            nav.navigationBar.tintColor = tint
        }
        vc.children.forEach { restyle($0, bar: bar, tint: tint) }
        if let presented = vc.presentedViewController { restyle(presented, bar: bar, tint: tint) }
        vc.view.setNeedsLayout()
    }

    // MARK: Disegni

    /// Una tessera dello sfondo disegnato, ripetibile.
    static func tile(_ wallpaper: VeloWallpaper, wall: VeloRGB) -> UIImage {
        let size = CGSize(width: 86, height: 86)
        let line = wall.blend(wall.onColor, 0.12).ui
        return UIGraphicsImageRenderer(size: size).image { ctx in
            wall.ui.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let path = VeloSVGPath.parse(wallpaper.path)
            path.lineWidth = wallpaper.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            line.setStroke()
            path.stroke()
        }
    }

    /// L'immagine dietro la chat (una tua foto, se scelta, vince su tutto).
    static func chatBackground(size: CGSize, palette p: Palette, pattern: String) -> UIImage {
        let size = CGSize(width: max(size.width, 320), height: max(size.height, 568))
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            switch pattern {
            case VeloWallpaper.gradient:
                let colors = [p.wall.ui.cgColor, p.wall.blend(p.tint, 0.5).ui.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
            case VeloWallpaper.glow:
                p.wall.ui.setFill()
                ctx.fill(rect)
                let colors = [p.wall.blend(p.tint, 0.35).ui.cgColor, p.wall.ui.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    let c = CGPoint(x: size.width / 2, y: size.height * 0.35)
                    ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width * 0.9, options: [.drawsAfterEndLocation])
                }
            default:
                if let w = VeloWallpaper.byId(pattern) {
                    UIColor(patternImage: tile(w, wall: p.wall)).setFill()
                } else {
                    p.wall.ui.setFill()
                }
                ctx.fill(rect)
            }
        }
    }

    static var currentChatBackground: UIImage {
        if let photo = MLImageManager.sharedInstance().getBackgroundFor(nil) { return photo }
        return chatBackground(size: UIScreen.main.bounds.size, palette: current, pattern: pattern)
    }

    /// Il carattere dei messaggi.
    static func font(size: CGFloat, design: String = VeloTheme.fontDesign) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        let wanted: UIFontDescriptor.SystemDesign = design == "rounded" ? .rounded : (design == "elegant" ? .serif : .default)
        if let desc = base.fontDescriptor.withDesign(wanted) { return UIFont(descriptor: desc, size: size) }
        return base
    }

    static func swiftUIFont(size: CGFloat) -> Font {
        let design: Font.Design = fontDesign == "rounded" ? .rounded : (fontDesign == "elegant" ? .serif : .default)
        return .system(size: size, design: design)
    }

    /// Raggio degli angoli della foto profilo per una certa misura.
    @objc static func avatarRadius(forSize size: CGFloat) -> CGFloat {
        switch avatarShape {
        case "soft": return size * 0.28
        case "square": return size * 0.08
        default: return size / 2
        }
    }

    @objc static var listLineCount: Int { listLines }
    @objc static var tintColor: UIColor { current.tintOnPage.ui }
    @objc static var pageColor: UIColor { current.page.ui }
}

// MARK: - Anteprima di una chat (in cima ad Aspetto e Personalizza)

struct VeloThemePreview: View {
    let palette: VeloTheme.Palette
    let pattern: String
    let corners: Int
    let textSize: Int
    let fontDesign: String
    var height: CGFloat = 230

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").foregroundColor(palette.onBar.color)
                Circle().fill(palette.onBar.color.opacity(0.25)).frame(width: 30, height: 30)
                    .overlay(Text("M").font(.system(size: 14, weight: .bold)).foregroundColor(palette.onBar.color))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Marco").font(.system(size: 15, weight: .semibold)).foregroundColor(palette.onBar.color)
                    Text("online").font(.system(size: 11)).foregroundColor(palette.onBar.color.opacity(0.75))
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(palette.bar.color)

            ZStack {
                Image(uiImage: VeloTheme.chatBackground(size: CGSize(width: 340, height: height), palette: palette, pattern: pattern))
                    .resizable().scaledToFill()
                VStack(spacing: 8) {
                    HStack {
                        bubble("Ti piace questo tema?", bg: palette.received, fg: palette.onReceived)
                        Spacer(minLength: 40)
                    }
                    HStack {
                        Spacer(minLength: 40)
                        bubble("Sì, lo tengo così", bg: palette.sent, fg: palette.onSent)
                    }
                }
                .padding(12)
            }
            .frame(height: height - 48)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12)))
    }

    private func bubble(_ text: String, bg: VeloRGB, fg: VeloRGB) -> some View {
        Text(text)
            .font(VeloThemePreview.font(textSize, fontDesign))
            .foregroundColor(fg.color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: CGFloat(corners)).fill(bg.color))
    }

    static func font(_ size: Int, _ design: String) -> Font {
        let d: Font.Design = design == "rounded" ? .rounded : (design == "elegant" ? .serif : .default)
        return .system(size: CGFloat(size), design: d)
    }
}

// MARK: - Aspetto

final class VeloThemeState: ObservableObject {
    @Published var tick = 0
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: VeloTheme.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tick += 1
        }
    }
}

struct VeloAppearanceView: View {
    @StateObject private var state = VeloThemeState()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = state.tick
        let palette = VeloTheme.palette(systemDark: scheme == .dark)
        Form {
            Section {
                VeloThemePreview(palette: palette, pattern: VeloTheme.pattern, corners: VeloTheme.corners,
                                 textSize: VeloTheme.textSize, fontDesign: VeloTheme.fontDesign)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            }

            Section(header: Text("Tema")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if VeloTheme.hasSaved {
                            Button { VeloTheme.loadMine() } label: {
                                card(name: "Il mio tema", colours: savedColours(), selected: VeloTheme.handMade)
                            }.buttonStyle(.plain)
                        }
                        ForEach(VeloPreset.all) { preset in
                            Button { VeloTheme.choose(preset: preset, accent: nil, autoNight: VeloTheme.autoNight) } label: {
                                card(name: preset.name, colours: VeloTheme.colours(of: preset, accent: nil),
                                     selected: !VeloTheme.handMade && VeloTheme.preset == preset)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Toggle("Modalità notte automatica (segue il telefono)", isOn: Binding(
                    get: { VeloTheme.autoNight },
                    set: { VeloTheme.setAutoNight($0) }))
                    .disabled(VeloTheme.handMade)
            }

            Section {
                NavigationLink(destination: VeloCustomizeView()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personalizza").font(.body.weight(.semibold))
                        Text("Scegli tu colori, sfondo, forme e testo").font(.footnote).foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Elenco delle chat")) {
                Picker("Righe per chat", selection: Binding(
                    get: { VeloTheme.listLines },
                    set: { VeloTheme.set($0, forKey: VeloTheme.kListLines) })) {
                    Text("2 righe").tag(2)
                    Text("3 righe").tag(3)
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Aspetto")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savedColours() -> VeloTheme.Colours {
        if let data = UserDefaults.standard.dictionary(forKey: VeloTheme.kSaved)?[VeloTheme.kColours] as? Data,
           let c = try? JSONDecoder().decode(VeloTheme.Colours.self, from: data) {
            return c
        }
        return VeloTheme.colours(of: .classico, accent: nil)
    }

    private func card(name: String, colours c: VeloTheme.Colours, selected: Bool) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                Rectangle().fill(c.bar.color).frame(height: 14)
                ZStack {
                    Rectangle().fill(c.wall.color)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 5).fill(c.received.color).frame(width: 34, height: 11)
                        HStack { Spacer(); RoundedRectangle(cornerRadius: 5).fill(c.sent.color).frame(width: 40, height: 11) }
                        RoundedRectangle(cornerRadius: 5).fill(c.received.color).frame(width: 26, height: 11)
                    }
                    .padding(7)
                }
            }
            .frame(width: 72, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1))
            Text(name).font(.caption).foregroundColor(.primary).lineLimit(1)
        }
        .frame(width: 76)
    }
}

// MARK: - Personalizza

struct VeloCustomizeView: View {
    @StateObject private var state = VeloThemeState()
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0
    @State private var part = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var savedNotice = false

    private let parts = ["Barra in alto", "Pulsanti", "I miei messaggi", "Ricevuti", "Sfondo chat", "Sfondo pagine"]

    var body: some View {
        let _ = state.tick
        let palette = VeloTheme.palette(systemDark: scheme == .dark)
        Form {
            Section {
                VeloThemePreview(palette: palette, pattern: VeloTheme.pattern, corners: VeloTheme.corners,
                                 textSize: VeloTheme.textSize, fontDesign: VeloTheme.fontDesign)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                Picker("", selection: $tab) {
                    Text("Colori").tag(0)
                    Text("Sfondo").tag(1)
                    Text("Forme").tag(2)
                    Text("Testo").tag(3)
                }
                .pickerStyle(.segmented)
            }

            switch tab {
            case 0: coloursSection(palette)
            case 1: wallSection(palette)
            case 2: shapesSection()
            default: textSection()
            }

            Section(footer: Text("Vedi subito il risultato qui sopra, e in tutta l'app quando torni indietro.")) {
                Button("Salva come il mio tema") {
                    VeloTheme.saveMine()
                    savedNotice = true
                }
                Button("Ripristina", role: .destructive) { VeloTheme.reset() }
            }
        }
        .navigationTitle("Personalizza")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Salvato: lo trovi in Aspetto, tra i temi", isPresented: $savedNotice) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data?) = result {
                    DispatchQueue.main.async {
                        MLImageManager.sharedInstance().saveBackgroundImageData(data, for: nil)
                        VeloTheme.set(VeloWallpaper.photo, forKey: VeloTheme.kPattern)
                    }
                }
            }
        }
    }

    // colori: tocchi una parte, poi scegli il colore; il testo si adatta da solo
    @ViewBuilder
    private func coloursSection(_ p: VeloTheme.Palette) -> some View {
        let values = [p.bar, p.tint, p.sent, p.received, p.wall, p.page]
        Section(footer: Text("Tocca una parte, poi scegli il colore. Il testo si adatta da solo.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parts.indices, id: \.self) { i in
                        Button { part = i } label: {
                            HStack(spacing: 6) {
                                Circle().fill(values[i].color).frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                                Text(parts[i]).font(.footnote)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(part == i ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(veloSwatches, id: \.self) { value in
                    Button { setPart(VeloRGB(value), palette: p) } label: {
                        Circle().fill(VeloRGB(value).color).frame(height: 30)
                            .overlay(Circle().stroke(values[part] == VeloRGB(value) ? Color.accentColor : Color.primary.opacity(0.15),
                                                     lineWidth: values[part] == VeloRGB(value) ? 3 : 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            ColorPicker("Un altro colore, scelto da te", selection: Binding(
                get: { values[part].color },
                set: { setPart(VeloRGB(UIColor($0)), palette: p) }), supportsOpacity: false)
        }
    }

    private func setPart(_ colour: VeloRGB, palette p: VeloTheme.Palette) {
        var c = VeloTheme.Colours(bar: p.bar, buttons: p.tint, sent: p.sent, received: p.received, wall: p.wall, page: p.page)
        switch part {
        case 0: c.bar = colour
        case 1: c.buttons = colour
        case 2: c.sent = colour
        case 3: c.received = colour
        case 4: c.wall = colour
        default: c.page = colour
        }
        VeloTheme.setColours(c)
    }

    @ViewBuilder
    private func wallSection(_ p: VeloTheme.Palette) -> some View {
        let options: [(String, String)] = [(VeloWallpaper.plain, "Tinta unita"), (VeloWallpaper.gradient, "Sfumato"), (VeloWallpaper.glow, "Bagliore")]
            + VeloWallpaper.drawings.map { ($0.id, $0.name) }
        Section(header: Text("Sfondo della chat")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        if VeloTheme.pattern == VeloWallpaper.photo {
                            MLImageManager.sharedInstance().saveBackgroundImageData(nil, for: nil)
                        }
                        VeloTheme.set(option.0, forKey: VeloTheme.kPattern)
                    } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: VeloTheme.chatBackground(size: CGSize(width: 100, height: 120), palette: p, pattern: option.0))
                                .resizable().scaledToFill()
                                .frame(height: 70).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloTheme.pattern == option.0 ? Color.accentColor : Color.primary.opacity(0.15),
                                                                                   lineWidth: VeloTheme.pattern == option.0 ? 3 : 1))
                            Text(option.1).font(.caption).foregroundColor(.primary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Una tua foto", systemImage: "photo")
            }
        }
    }

    @ViewBuilder
    private func shapesSection() -> some View {
        Section(header: Text("Angoli dei messaggi")) {
            Picker("", selection: Binding(get: { VeloTheme.corners }, set: { VeloTheme.set($0, forKey: VeloTheme.kCorners) })) {
                Text("Squadrati").tag(4)
                Text("Leggeri").tag(10)
                Text("Tondi").tag(18)
                Text("Pieni").tag(26)
            }
            .pickerStyle(.segmented)
        }
        Section(header: Text("Forma delle foto profilo")) {
            Picker("", selection: Binding(get: { VeloTheme.avatarShape }, set: { VeloTheme.set($0, forKey: VeloTheme.kAvatar) })) {
                Text("Tonda").tag("round")
                Text("Morbida").tag("soft")
                Text("Quadrata").tag("square")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func textSection() -> some View {
        Section(header: Text("Grandezza del testo")) {
            Picker("", selection: Binding(get: { VeloTheme.textSize }, set: { VeloTheme.set($0, forKey: VeloTheme.kTextSize) })) {
                Text("Aa").font(.system(size: 12)).tag(13)
                Text("Aa").font(.system(size: 14)).tag(15)
                Text("Aa").font(.system(size: 16)).tag(17)
                Text("Aa").font(.system(size: 19)).tag(20)
            }
            .pickerStyle(.segmented)
        }
        Section(header: Text("Carattere")) {
            let fonts = [("modern", "Moderno"), ("rounded", "Morbido"), ("elegant", "Elegante")]
            ForEach(fonts.indices, id: \.self) { index in
                let option = fonts[index]
                Button {
                    VeloTheme.set(option.0, forKey: VeloTheme.kFont)
                } label: {
                    HStack {
                        Text(option.1).font(VeloThemePreview.font(17, option.0)).foregroundColor(.primary)
                        Spacer()
                        if VeloTheme.fontDesign == option.0 { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                    }
                }
            }
        }
    }
}
