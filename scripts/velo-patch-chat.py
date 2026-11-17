# Velo: la libreria della chat (ExyteChat) ha angoli e testo fissi; qui li leggiamo da Aspetto/Personalizza
# (UserDefaults veloBubbleCorners, veloTextSize, veloFontDesign). Esce con errore se il sorgente cambia.
# SPDX-License-Identifier: AGPL-3.0-only
import pathlib, sys

root = pathlib.Path(sys.argv[1])
msg = list(root.glob("checkouts/*/Sources/ExyteChat/Views/MessageView/MessageView.swift"))
par = list(root.glob("checkouts/*/Sources/ExyteChat/Views/ChatCustomizationParameters.swift"))
if len(msg) != 1 or len(par) != 1:
    sys.exit("ExyteChat non trovato: %s %s" % (msg, par))

def patch(path, old, new):
    s = path.read_text(encoding="utf-8")
    if s.count(old) != 1:
        sys.exit("testo non trovato in %s: %r" % (path, old))
    path.write_text(s.replace(old, new), encoding="utf-8")

patch(msg[0], "let radius: CGFloat = !message.attachments.isEmpty ? 12 : 20",
      'let radius: CGFloat = !message.attachments.isEmpty ? 12 : CGFloat((UserDefaults.standard.object(forKey: "veloBubbleCorners") as? Int) ?? 18)')
patch(par[0], "var font = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15))",
      "var font = UIFontMetrics.default.scaledFont(for: veloChatFont())")
s = par[0].read_text(encoding="utf-8")
s += '''

// Velo: grandezza e carattere dei messaggi scelti in Personalizza
func veloChatFont() -> UIFont {
    let size = CGFloat((UserDefaults.standard.object(forKey: "veloTextSize") as? Int) ?? 15)
    let base = UIFont.systemFont(ofSize: size)
    let design = UserDefaults.standard.string(forKey: "veloFontDesign")
    let wanted: UIFontDescriptor.SystemDesign = design == "rounded" ? .rounded : (design == "elegant" ? .serif : .default)
    if let d = base.fontDescriptor.withDesign(wanted) { return UIFont(descriptor: d, size: size) }
    return base
}
'''
par[0].write_text(s, encoding="utf-8")
print("ExyteChat adattato:", msg[0].parent.parent.parent.parent.parent.name)
