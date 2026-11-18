// Velo iOS — protezione del telefono, allineata alla Velo Android:
//  - PIN di sblocco facoltativo (min 6 cifre; dopo 5 errori attesa da 30 s a 15 min, anche dopo un riavvio)
//  - PIN antipanico (diverso da quello di sblocco): cancella tutta Velo da questo telefono e la chiude
//  - cancellazione automatica se Velo non viene sbloccata per 3/7/14/30 giorni (serve il PIN)
//  - copertura del contenuto nell'elenco app e durante registrazione/duplicazione dello schermo
//  - contenuto escluso dagli screenshot (contenitore "secure" di UIKit)
// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import CommonCrypto
import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Memoria (Keychain, solo questo dispositivo)

enum VeloSecureStore {
    private static let service = "velo.lock"

    static func data(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func set(_ key: String, _ value: Data?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value = value else { return }
        var add = base
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func double(_ key: String) -> Double {
        guard let d = data(key), let s = String(data: d, encoding: .utf8), let v = Double(s) else { return 0 }
        return v
    }

    static func setDouble(_ key: String, _ v: Double) { set(key, Data(String(v).utf8)) }
}

// MARK: - PIN

enum VeloPinCheck: Equatable {
    case unlocked, panic, wrong, wait(Int)
}

enum VeloPin {
    static let minLength = 6
    private static let iterations: UInt32 = 200_000

    static var hasPin: Bool { VeloSecureStore.data("pin.hash") != nil }
    static var hasPanicPin: Bool { VeloSecureStore.data("panic.hash") != nil }

    private static func hash(_ pin: String, salt: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pin.utf8)
        _ = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &out, out.count)
        }
        return Data(out)
    }

    private static func store(_ pin: String, prefix: String) {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        VeloSecureStore.set("\(prefix).salt", Data(salt))
        VeloSecureStore.set("\(prefix).hash", hash(pin, salt: Data(salt)))
    }

    private static func matches(_ pin: String, prefix: String) -> Bool {
        guard let salt = VeloSecureStore.data("\(prefix).salt"), let h = VeloSecureStore.data("\(prefix).hash") else { return false }
        let computed = hash(pin, salt: salt)
        guard computed.count == h.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<h.count { diff |= computed[i] ^ h[i] }
        return diff == 0
    }

    static func isValidNew(_ pin: String) -> Bool { pin.count >= minLength && pin.allSatisfy { $0.isNumber } }

    static func setPin(_ pin: String) { store(pin, prefix: "pin"); markUnlocked() }
    static func setPanicPin(_ pin: String) { store(pin, prefix: "panic") }
    static func isUnlockPin(_ pin: String) -> Bool { matches(pin, prefix: "pin") }

    static func removePin() {
        for k in ["pin.hash", "pin.salt", "panic.hash", "panic.salt", "fail.count", "fail.until"] { VeloSecureStore.set(k, nil) }
        VeloAutoWipe.days = 0
    }

    static func removePanicPin() {
        VeloSecureStore.set("panic.hash", nil)
        VeloSecureStore.set("panic.salt", nil)
    }

    /// L'antipanico non aspetta mai; il PIN di sblocco sì, dopo 5 errori.
    static func check(_ pin: String) -> VeloPinCheck {
        if hasPanicPin && matches(pin, prefix: "panic") { return .panic }
        let until = VeloSecureStore.double("fail.until")
        let now = Date().timeIntervalSince1970
        if until > now { return .wait(Int(until - now) + 1) }
        if matches(pin, prefix: "pin") {
            VeloSecureStore.setDouble("fail.count", 0)
            VeloSecureStore.setDouble("fail.until", 0)
            markUnlocked()
            return .unlocked
        }
        let fails = VeloSecureStore.double("fail.count") + 1
        VeloSecureStore.setDouble("fail.count", fails)
        if fails >= 5 {
            // 30 s, 60 s, 120 s ... fino a 15 minuti
            let wait = min(900.0, 30.0 * pow(2.0, fails - 5))
            VeloSecureStore.setDouble("fail.until", now + wait)
            return .wait(Int(wait))
        }
        return .wrong
    }

    static func markUnlocked() {
        VeloSecureStore.setDouble("last.unlock", Date().timeIntervalSince1970)
        VeloAutoWipe.scheduleWarning()
    }
}

// MARK: - Cancellazione automatica

enum VeloAutoWipe {
    static let choices = [0, 3, 7, 14, 30]

    static var days: Int {
        get { Int(VeloSecureStore.double("autowipe.days")) }
        set { VeloSecureStore.setDouble("autowipe.days", Double(newValue)); scheduleWarning() }
    }

    static var isDue: Bool {
        guard VeloPin.hasPin, days > 0 else { return false }
        let last = VeloSecureStore.double("last.unlock")
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last > Double(days) * 86400
    }

    /// Avviso locale un giorno prima della cancellazione (come la Velo Android).
    static func scheduleWarning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["velo.autowipe"])
        guard VeloPin.hasPin, days > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Velo"
        content.body = "Domani Velo si cancella da questo telefono se non la sblocchi."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(days - 1) * 86400, repeats: false)
        center.add(UNNotificationRequest(identifier: "velo.autowipe", content: content, trigger: trigger))
    }
}

// MARK: - Cancellazione totale (antipanico / autodistruzione)

enum VeloWipe {
    /// PIN antipanico: come la Velo Android chiede ai contatti Velo di cancellare le chat
    /// ("cancella per entrambi"), poi cancella tutto qui. Aspetta la connessione al massimo 12 s.
    static func panicAndExit() {
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = MLXMPPManager.sharedInstance()
            func accounts() -> [xmpp] { manager.connectedXMPP.compactMap { $0 as? xmpp } }
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline && accounts().contains(where: { !$0.veloIsBound() }) {
                Thread.sleep(forTimeInterval: 0.25)
            }
            var sent = 0
            let contacts = DataLayer.sharedInstance().contactList()
            for account in accounts() where account.veloIsBound() {
                for contact in contacts where contact.accountID == account.accountID && !contact.isMuc && !contact.isSelf {
                    if account.veloSendHistoryPurge(to: contact) { sent += 1 }
                }
            }
            if sent > 0 { Thread.sleep(forTimeInterval: 3) }
            DispatchQueue.main.async { everythingAndExit() }
        }
    }

    /// Come clearApplicationUserData() della Velo Android: chiavi, account, chat, file, impostazioni. Poi chiude.
    static func everythingAndExit() -> Never {
        for cls in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassKey, kSecClassCertificate, kSecClassIdentity] {
            SecItemDelete([kSecClass as String: cls] as CFDictionary)
        }
        let fm = FileManager.default
        var roots: [URL] = []
        for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory, .cachesDirectory, .libraryDirectory] {
            roots += fm.urls(for: dir, in: .userDomainMask)
        }
        roots.append(fm.temporaryDirectory)
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) { roots.append(group) }
        for root in roots {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
        }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        UserDefaults(suiteName: kAppGroup)?.removePersistentDomain(forName: kAppGroup)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        exit(0)
    }
}

// MARK: - Schermata di sblocco

struct VeloLockView: View {
    let onUnlock: () -> Void
    @State private var pin = ""
    @State private var message = "Inserisci il PIN"
    @State private var isError = false
    @State private var wiping = false

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        ZStack {
            Color(red: 0x1F / 255.0, green: 0x25 / 255.0, blue: 0x57 / 255.0).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("Velo").font(.system(size: 40, weight: .bold)).foregroundColor(.white)
                Text(message).foregroundColor(isError ? Color(red: 1, green: 0.78, blue: 0) : .white.opacity(0.85))
                HStack(spacing: 14) {
                    ForEach(0..<max(VeloPin.minLength, pin.count), id: \.self) { i in
                        Circle().fill(i < pin.count ? Color.white : Color.white.opacity(0.25)).frame(width: 14, height: 14)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84)), count: 3), spacing: 18) {
                    ForEach(keys, id: \.self) { k in
                        if k.isEmpty {
                            Color.clear.frame(width: 72, height: 72)
                        } else {
                            Button(action: { tap(k) }) {
                                Text(k).font(.system(size: 30, weight: .medium)).foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Circle().fill(Color.white.opacity(k == "⌫" ? 0 : 0.12)))
                            }
                        }
                    }
                }
                Button(action: confirm) {
                    Text("Sblocca").font(.headline).foregroundColor(Color(red: 0x1F / 255.0, green: 0x25 / 255.0, blue: 0x57 / 255.0))
                        .frame(width: 220, height: 50)
                        .background(Capsule().fill(Color(red: 0x7C / 255.0, green: 0x8C / 255.0, blue: 1)))
                }
                .disabled(pin.isEmpty || wiping)
                Spacer()
            }
        }
    }

    private func tap(_ k: String) {
        if k == "⌫" { if !pin.isEmpty { pin.removeLast() }; return }
        if pin.count < 16 { pin.append(k) }
    }

    private func confirm() {
        let attempt = pin
        pin = ""
        switch VeloPin.check(attempt) {
        case .unlocked:
            onUnlock()
        case .panic:
            wiping = true
            VeloWipe.panicAndExit()
        case .wrong:
            isError = true
            message = "PIN sbagliato"
        case .wait(let s):
            isError = true
            message = "Troppi tentativi: riprova tra \(s) s"
        }
    }
}

// MARK: - Controllo del blocco (usato da MonalAppDelegate)

@objc class VeloLockController: NSObject {
    @objc static let shared = VeloLockController()

    private weak var mainWindow: UIWindow?
    private var lockWindow: UIWindow?
    private var coverWindow: UIWindow?
    private var needsLock = true
    private var secured = false

    /// Da chiamare a fine avvio, quando la finestra principale esiste.
    @objc func attach(to window: UIWindow?) {
        guard let window = window, mainWindow == nil else { return }
        mainWindow = window
        if VeloAutoWipe.isDue { VeloWipe.everythingAndExit() }
        secureAgainstScreenshots(window)
        NotificationCenter.default.addObserver(self, selector: #selector(captureChanged),
                                               name: UIScreen.capturedDidChangeNotification, object: nil)
        //cancellazione a distanza ordinata dall'admin del server (RemoteWipe della Velo Android)
        NotificationCenter.default.addObserver(forName: Notification.Name("VeloRemoteWipe"), object: nil, queue: .main) { _ in
            VeloWipe.everythingAndExit()
        }
        needsLock = true
        showLockIfNeeded()
    }

    @objc func appWillResignActive() { showCover() }

    @objc func appDidEnterBackground() {
        needsLock = true
        showCover()
    }

    @objc func appDidBecomeActive() {
        if VeloAutoWipe.isDue { VeloWipe.everythingAndExit() }
        showLockIfNeeded()
        if lockWindow == nil && !(mainWindow?.screen.isCaptured ?? false) { hideCover() }
    }

    @objc private func captureChanged() {
        if mainWindow?.screen.isCaptured ?? false { showCover() } else if lockWindow == nil { hideCover() }
    }

    private func scene() -> UIWindowScene? { mainWindow?.windowScene }

    private func showLockIfNeeded() {
        guard needsLock, VeloPin.hasPin, lockWindow == nil, let scene = scene() else {
            if !VeloPin.hasPin { needsLock = false }
            return
        }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 2
        w.rootViewController = UIHostingController(rootView: VeloLockView { [weak self] in
            self?.needsLock = false
            self?.lockWindow?.isHidden = true
            self?.lockWindow = nil
            self?.hideCover()
            self?.mainWindow?.makeKey()
        })
        w.makeKeyAndVisible()
        lockWindow = w
    }

    private func showCover() {
        guard coverWindow == nil, let scene = scene() else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let vc = UIViewController()
        vc.view.backgroundColor = UIColor(red: 0x1F / 255.0, green: 0x25 / 255.0, blue: 0x57 / 255.0, alpha: 1)
        let label = UILabel()
        label.text = "Velo"
        label.font = .systemFont(ofSize: 40, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                                     label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)])
        w.rootViewController = vc
        w.isHidden = false
        coverWindow = w
    }

    private func hideCover() {
        coverWindow?.isHidden = true
        coverWindow = nil
    }

    /// Il contenuto della finestra principale finisce dentro il livello di un campo "secure" di UIKit:
    /// iOS lo toglie da screenshot e registrazioni (al suo posto resta vuoto). Non è un'API ufficiale:
    /// se il livello interno non c'è, non si fa nulla e restano la copertura e il rilevamento.
    private func secureAgainstScreenshots(_ window: UIWindow) {
        guard !secured else { return }
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        guard let superlayer = window.layer.superlayer else { return }
        //il campo resta nell'origine (0,0) con dimensione zero: il suo livello "canvas" ospita quello della
        //finestra senza spostarlo (centrarlo spostava tutta l'app di mezzo schermo)
        field.frame = .zero
        field.leftView = UIView(frame: .zero)
        field.leftViewMode = .always
        window.addSubview(field)
        superlayer.addSublayer(field.layer)
        //il livello "canvas" del campo secure (nome interno di UIKit); se non c'è, ultimo sottolivello
        let canvas = field.layer.sublayers?.first { String(describing: type(of: $0.delegate as Any)).contains("Canvas") }
        guard let secureLayer = canvas ?? field.layer.sublayers?.last else {
            field.removeFromSuperview()
            return
        }
        secureLayer.addSublayer(window.layer)
        secured = true
    }
}

// MARK: - Impostazioni

struct VeloSecuritySettings: View {
    @State private var hasPin = VeloPin.hasPin
    @State private var hasPanic = VeloPin.hasPanicPin
    @State private var autoWipe = VeloAutoWipe.days
    @State private var entry: Entry?
    @State private var alert: String?

    enum Entry: Identifiable {
        case newPin, changePin, newPanic
        var id: Int { switch self { case .newPin: return 0; case .changePin: return 1; case .newPanic: return 2 } }
    }

    var body: some View {
        Form {
            Section(header: Text("Blocco di Velo"), footer: Text("Con il PIN Velo si blocca ogni volta che esci dall'app. Dopo 5 errori bisogna aspettare, da 30 secondi fino a 15 minuti.")) {
                if hasPin {
                    Button("Cambia PIN") { entry = .changePin }
                    Button("Togli il PIN", role: .destructive) {
                        VeloPin.removePin(); refresh()
                    }
                } else {
                    Button("Imposta il PIN") { entry = .newPin }
                }
            }
            if hasPin {
                Section(header: Text("PIN antipanico"), footer: Text("Se lo scrivi al posto del PIN, Velo cancella in silenzio tutto da questo telefono (account, chiavi, chat, file) e si chiude. Deve essere diverso dal PIN di sblocco.")) {
                    if hasPanic {
                        Button("Togli il PIN antipanico", role: .destructive) { VeloPin.removePanicPin(); refresh() }
                    } else {
                        Button("Imposta il PIN antipanico") { entry = .newPanic }
                    }
                }
                Section(header: Text("Cancellazione automatica"), footer: Text("Se Velo non viene sbloccata per questo tempo, si cancella da questo telefono. Un giorno prima arriva un avviso. Le chat sugli altri telefoni restano.")) {
                    Picker("Cancella se non sbloccata da", selection: $autoWipe) {
                        ForEach(VeloAutoWipe.choices, id: \.self) { d in
                            Text(d == 0 ? "Mai" : "\(d) giorni").tag(d)
                        }
                    }
                    .onChange(of: autoWipe) { VeloAutoWipe.days = autoWipe }
                }
            }
            VeloKeepAliveSection()
        }
        .navigationBarTitle(Text("Blocco e antipanico"), displayMode: .inline)
        .sheet(item: $entry) { e in
            VeloPinEntry(title: e == .newPanic ? "Nuovo PIN antipanico" : "Nuovo PIN") { pin in
                guard VeloPin.isValidNew(pin) else { alert = "Il PIN deve avere almeno \(VeloPin.minLength) cifre."; return }
                if e == .newPanic {
                    guard !VeloPin.isUnlockPin(pin) else { alert = "Il PIN antipanico deve essere diverso da quello di sblocco."; return }
                    VeloPin.setPanicPin(pin)
                } else {
                    VeloPin.removePanicPin()
                    VeloPin.setPin(pin)
                }
                entry = nil
                refresh()
            }
        }
        .alert(isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Alert(title: Text("Velo"), message: Text(alert ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private func refresh() {
        hasPin = VeloPin.hasPin
        hasPanic = VeloPin.hasPanicPin
        autoWipe = VeloAutoWipe.days
    }
}

struct VeloPinEntry: View {
    let title: String
    let onDone: (String) -> Void
    @State private var first = ""
    @State private var second = ""
    @State private var mismatch = false

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text(mismatch ? "I due PIN non coincidono." : "Almeno \(VeloPin.minLength) cifre.")) {
                    SecureField("PIN", text: $first).keyboardType(.numberPad)
                    SecureField("Ripeti il PIN", text: $second).keyboardType(.numberPad)
                }
                Button("Salva") {
                    if first != second { mismatch = true; return }
                    onDone(first)
                }
                .disabled(first.isEmpty || second.isEmpty)
            }
            .navigationBarTitle(Text(title), displayMode: .inline)
        }
    }
}

// MARK: - Sempre collegata (prova): audio muto in background

/// VELO (prova): iOS congela le app in background dopo ~30 s, e con loro il Tor interno. Un suono muto in ciclo
/// (categoria playback, mescolato agli altri suoni, volume zero) tiene Velo sveglia e collegata, cosi' i messaggi
/// arrivano subito. Costa batteria; iOS puo' comunque chiudere l'app se serve memoria. Spento di partenza.
@objc class VeloKeepAlive: NSObject {
    @objc static let shared = VeloKeepAlive()
    private static let enabledKey = "veloKeepAlive"
    private var player: AVAudioPlayer?
    /// true se l'audio ha girato senza interruzioni dall'ultima uscita (Tor non e' mai stato congelato)
    @objc private(set) var ranWholeBackground = false
    @objc private(set) var isRunning = false

    @objc static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    /// Un secondo di silenzio, WAV mono 8 kHz 16 bit, fatto in memoria.
    private static func silentWav() -> Data {
        let rate: UInt32 = 8000, samples: UInt32 = 8000
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + samples * 2); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(samples * 2); d.append(Data(count: Int(samples * 2)))
        return d
    }

    @objc func startIfEnabled() {
        ranWholeBackground = false
        guard VeloKeepAlive.isEnabled else { return }
        ranWholeBackground = start()
    }

    @discardableResult private func start() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if player == nil {
                player = try AVAudioPlayer(data: VeloKeepAlive.silentWav())
                player?.numberOfLoops = -1
                player?.volume = 0
            }
            player?.play()
            isRunning = player?.isPlaying ?? false
            DDLogInfo("VELO: sempre collegata, audio muto avviato: \(isRunning)")
            return isRunning
        } catch {
            DDLogError("VELO: sempre collegata, audio muto non avviato: \(error)")
            isRunning = false
            return false
        }
    }

    @objc func stop() {
        guard player != nil || isRunning else { return }
        player?.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        DDLogInfo("VELO: sempre collegata, audio muto fermato")
    }

    @objc private func interrupted(_ note: Notification) {
        guard isRunning || ranWholeBackground,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            // chiamata, sveglia...: iOS ferma il suono e puo' congelare l'app, Tor andra' risvegliato
            isRunning = false
            ranWholeBackground = false
            DDLogInfo("VELO: sempre collegata, audio interrotto")
        } else if type == .ended && UIApplication.shared.applicationState == .background && VeloKeepAlive.isEnabled {
            DDLogInfo("VELO: sempre collegata, riparto dopo l'interruzione")
            start()
        }
    }

    @objc private func mediaReset() {
        player = nil
        if isRunning && VeloKeepAlive.isEnabled { start() }
    }
}

struct VeloKeepAliveSection: View {
    @State private var enabled = VeloKeepAlive.isEnabled
    var body: some View {
        Section(header: Text("Connessione"), footer: Text("Prova: in background Velo resta sveglia con un suono muto, cosi' Tor e la connessione non si fermano e i messaggi arrivano subito. Consuma piu' batteria. Non chiudere Velo dal selettore delle app, altrimenti si ferma comunque.")) {
            Toggle("Sempre collegata (prova)", isOn: $enabled)
                .onChange(of: enabled) { VeloKeepAlive.isEnabled = enabled }
        }
    }
}

// MARK: - Diagnostica connessione (come VeloDiagnosticsActivity della Android, in piccolo)

struct VeloDiagnosticsView: View {
    @ObservedObject var tor = VeloTorStatus.shared

    private func accountRows() -> [(String, String, Bool)] {
        let list = (MLXMPPManager.sharedInstance().connectedXMPP as? [xmpp]) ?? []
        return list.map { account in
            let bound = account.accountState.rawValue >= xmppState.stateBound.rawValue
            let name = HelperTools.veloShortJid(account.connectionProperties.identity.jid)
            return (name, bound ? "Collegato" : "Non collegato", bound)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 3)) { _ in
            Form {
                Section(header: Text("Tor"), footer: Text("Verde vuol dire che Tor ha i suoi circuiti e che gli account sono collegati: i messaggi passano davvero.")) {
                    HStack(spacing: 10) {
                        Circle().fill(tor.color).frame(width: 10, height: 10)
                        Text(tor.statusText)
                    }
                }
                Section(header: Text("Account")) {
                    let rows = accountRows()
                    if rows.isEmpty {
                        Text("Nessun account attivo").foregroundColor(.secondary)
                    }
                    ForEach(rows, id: \.0) { row in
                        HStack {
                            Text(row.0)
                            Spacer()
                            Text(row.1).foregroundColor(row.2 ? .green : .orange)
                        }
                    }
                }
                Section(header: Text("In background")) {
                    HStack {
                        Text("Sempre collegata (prova)")
                        Spacer()
                        Text(VeloKeepAlive.isEnabled ? "Accesa" : "Spenta").foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Versione")) {
                    Text(HelperTools.appBuildVersionInfo(for: .IQ)).font(.footnote).textSelection(.enabled)
                }
            }
        }
        .navigationBarTitle(Text("Diagnostica connessione"), displayMode: .inline)
    }
}
