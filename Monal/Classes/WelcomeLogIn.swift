//
//  WelcomeLogIn.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import CryptoKit

struct WelcomeLogIn: View {
    static private let credFaultyPattern = "^.+@.+\\..{2,}$"
    
    var advancedMode: Bool = false
    var delegate: SheetDismisserProtocol

    @State private var isEditingJid: Bool = false
    @State private var jid: String = ""
    @State private var isEditingPassword: Bool = false
    @State private var password: String = ""

    @State private var hardcodedServer: String = ""
    @State private var hardcodedPort: String = "5222"
    @State private var allowPlainAuth: Bool = false
    @State private var forceDirectTLS: Bool = false

    @State private var showAlert = false
    @State private var showQRCodeScanner = false

    // login related
    @State private var currentTimeout : DispatchTime? = nil
    @State private var errorObserverEnabled = false
    @State private var newAccountID: NSNumber? = nil
    @State private var loginComplete = false
    @State private var isLoadingOmemoBundles = false
    
    @State private var alertPrompt = AlertPrompt()
    @StateObject private var overlay = LoadingOverlayState()

#if IS_ALPHA
    let appLogoId = ImageResource.alphaAppLogo
#else
    let appLogoId = ImageResource.appLogo
#endif
    
    private var credentialsEnteredAlert: Bool {
        alertPrompt.title = Text("Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered both a username and password.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsEntered
    }

    private var credentialsFaultyAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("Your XMPP jid should be in in the format user@domain.tld. For special configurations, use manual setup.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertPrompt.title = Text("Duplicate jid!")
        alertPrompt.message = Text("This account already exists in Monal.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsExist
    }

    private func showTimeoutAlert() {
        DDLogVerbose("Showing timeout alert...")
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Timeout Error")
        alertPrompt.message = Text("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.")
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showSuccessAlert() {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected.")
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showLoginErrorAlert(errorMessage: String) {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Error")
        alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showPlainAuthWarningAlert() {
        alertPrompt.title = Text("Warning")
        alertPrompt.message = Text("If you turn this on, you will no longer be safe from man-in-the-middle attacks. Such attacks enable the adversary to manipulate your incoming and outgoing messages, add their own OMEMO keys, change your account details and even know or change your password!\n\nYou should rather switch to another server than turning this on.")
        alertPrompt.dismissLabel = Text("Understood")
        showAlert = true
    }

    private var jidDomainPart: String {
        let jidComponents = HelperTools.splitJid(jid)
        return jidComponents["host"] ?? ""
    }

    private var credentialsEntered: Bool {
        return !jid.isEmpty && !password.isEmpty
    }
    
    //VELO: come su Android si entra col solo nome utente; il dominio del gruppo si aggiunge da solo
    private var veloUsernameOnly: Bool {
        return !advancedMode && !jid.contains("@")
    }

    private var effectiveJid: String {
        return veloUsernameOnly ? "\(jid)@\(kVeloLoginDomain)" : jid
    }

    private var credentialsFaulty: Bool {
        if veloUsernameOnly {
            return jid.range(of: "^[a-z0-9._-]+$", options:.regularExpression) == nil
        }
        return jid.range(of: WelcomeLogIn.credFaultyPattern, options:.regularExpression) == nil
    }
    
    private var credentialsExist: Bool {
        let components = effectiveJid.components(separatedBy: "@")
        return DataLayer.sharedInstance().doesAccountExistUser(components[0], andDomain:components[1])
    }

    private var loginButtonDisabled: Bool {
        return !credentialsEntered || credentialsFaulty
    }
    
    private func startLoginTimeout() {
        let newTimeout = DispatchTime.now() + 30.0;
        self.currentTimeout = newTimeout
        DispatchQueue.main.asyncAfter(deadline: newTimeout) {
            if(newTimeout == self.currentTimeout) {
                DDLogWarn("First login timeout triggered...")
                if(self.newAccountID != nil) {
                    DDLogVerbose("Removing account...")
                    MLXMPPManager.sharedInstance().removeAccount(forAccountID: self.newAccountID!)
                    self.newAccountID = nil
                }
                self.currentTimeout = nil
                showTimeoutAlert()
            }
        }
    }
    
    private func submit() {
        showAlert = !credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert

        if (!showAlert) {
            startLoginTimeout()
            showLoadingOverlay(overlay, headline:"Logging in")
            self.errorObserverEnabled = true
            if veloUsernameOnly {
                //VELO: server del gruppo raggiunto sul suo indirizzo .onion via Tor, STARTTLS sulla 5222
                self.newAccountID = MLXMPPManager.sharedInstance().login(self.effectiveJid, password: self.password, hardcodedServer:kVeloOnionHost, hardcodedPort:kVeloOnionPort, forceDirectTLS: false, allowPlainAuth: false)
            } else if advancedMode {
                self.newAccountID = MLXMPPManager.sharedInstance().login(self.jid, password: self.password, hardcodedServer:self.hardcodedServer, hardcodedPort:self.hardcodedPort, forceDirectTLS: self.forceDirectTLS, allowPlainAuth: self.allowPlainAuth)
            } else {
                self.newAccountID = MLXMPPManager.sharedInstance().login(self.jid, password: self.password)
            }
            if(self.newAccountID == nil) {
                currentTimeout = nil // <- disable timeout on error
                errorObserverEnabled = false
                showLoginErrorAlert(errorMessage:NSLocalizedString("Account already configured in Monal!", comment: ""))
                self.newAccountID = nil
            }
        }
    }

    var body: some View {
        ZStack {
            /// Ensure the ZStack takes the entire area
            Color.clear
            
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        if !advancedMode {
                            VStack {
                                HStack () {
                                    Image(appLogoId)
                                        .resizable()
                                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .padding()

                                    Text("Log in to your existing account or register a new account. If required you will find more advanced options in Monal settings.")
                                        .padding()
                                        .padding(.leading, -16.0)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.systemBackground))
                        }

                        Form {
                            Text("I already have an account:")
                                .listRowSeparator(.hidden)
                            
                            TextField(advancedMode ? NSLocalizedString("user@domain.tld", comment: "placeholder when adding account") : "Nome utente", text: Binding(
                                get: { self.jid },
                                set: { string in self.jid = string.lowercased().replacingOccurrences(of: " ", with: "") }), onEditingChanged: { isEditingJid = $0 }
                            )
                            .textInputAutocapitalization(.never)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .submitLabel(.continue)
                            .addClearButton(isEditing: isEditingJid, text: $jid)
                            .listRowSeparator(.hidden)
                            
                            SecureField(NSLocalizedString("Password", comment: "placeholder when adding account"), text: $password)
                                .submitLabel(.go)
                                .onSubmit(submit)
                                .addClearButton(isEditing:  password.count > 0, text: $password)
                                .listRowSeparator(.hidden)

                            if advancedMode {
                                TextField(NSLocalizedString("Optional Hardcoded Hostname", comment: "advanced account settings"), text: $hardcodedServer)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .submitLabel(.go)
                                    .onSubmit(submit)
                                    .addClearButton(isEditing:  hardcodedServer.count > 0, text: $hardcodedServer)
                                    .listRowSeparator(.hidden)

                                if !hardcodedServer.isEmpty {
                                    HStack {
                                        Text("Port")
                                        Spacer()
                                        TextField(NSLocalizedString("Optional Hardcoded Port", comment: "advanced account settings"), text: $hardcodedPort)
                                            .keyboardType(.numberPad)
                                            .submitLabel(.go)
                                            .onSubmit(submit)
                                            .addClearButton(isEditing:  hardcodedPort.count > 0, text: $hardcodedPort)
                                            .onDisappear {
                                                hardcodedPort = "5222"
                                            }
                                    }
                                    .listRowSeparator(.hidden)

                                    Toggle(isOn: $forceDirectTLS) {
                                        Text("Always use direct TLS, not STARTTLS")
                                    }
                                    .onDisappear {
                                        forceDirectTLS = false
                                    }
                                }

                                Toggle(isOn: $allowPlainAuth) {
                                    Text("Allow MITM-prone PLAIN authentication")
                                }
                                // TODO: use the SCRAM preload list instead of hardcoding servers
                                .disabled(["yax.im", "conversations.im"].contains(jidDomainPart.lowercased()))
                                .onChange(of: jid) {
                                    if ["yax.im", "conversations.im"].contains(jidDomainPart.lowercased()) {
                                        allowPlainAuth = false
                                    }
                                }
                                .onChange(of: allowPlainAuth) {
                                    if allowPlainAuth {
                                        showPlainAuthWarningAlert()
                                    }
                                }
                            }

                            HStack() {
                                Button(action: submit) {
                                    Text("Login")
                                        .frame(maxWidth: .infinity)
                                        .padding(9.0)
                                        .background(Color(UIColor.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(loginButtonDisabled)
                                .alert(isPresented: $showAlert) {
                                    Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                                        if(self.loginComplete == true) {
                                            self.delegate.dismiss()
                                        }
                                    }))
                                }

                                if !advancedMode {
                                    // Just sets the credential in jid and password variables and shows them in the input fields
                                    // so user can control what they scanned and if o.k. login via the "Login" button.
                                    Button(action: {
                                        showQRCodeScanner = true
                                    }){
                                        Image(systemName: "qrcode")
                                            .frame(maxHeight: .infinity)
                                            .padding(9.0)
                                            .background(Color(UIColor.tertiarySystemFill))
                                            .foregroundColor(.primary)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .sheet(isPresented: $showQRCodeScanner) {
                                        Text("QR-Code Scanner").font(.largeTitle.weight(.bold))
                                        // Get existing credentials from QR and put values in jid and password
                                        MLQRCodeScanner(
                                            handleLogin: { jid, password in
                                                self.jid = jid
                                                self.password = password
                                            }, handleClose: {
                                                self.showQRCodeScanner = false
                                            }
                                        )
                                    }
                                }

                            }
                            .listRowSeparator(.hidden, edges: .top)
                            // Align the (bottom) list row separator to the very left
                            .alignmentGuide(.listRowSeparatorLeading) { _ in
                                return 0
                            }

                            //VELO: come su Android si entra nei gruppi con un invito (link, QR qui sopra o incollato),
                            //non con la registrazione libera di Monal
                            Button(action: {
                                VeloInviteFlow.start(text: UIPasteboard.general.string, from: nil)
                            }) {
                                Text("Ho un invito: incollalo")
                                    .foregroundColor(Color.accentColor)
                            }
                            
                            if(DataLayer.sharedInstance().enabledAccountCnts() == 0) {
                                Button(action: {
                                    self.delegate.dismiss()
                                }){
                                    Text("Set up account later")
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 10.0)
                                        .padding(.bottom, 9.0)
                                        .foregroundColor(Color(UIColor.systemGray))
                                }
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 30))
                        }
                    }
                    /// Sets the minimum frame height to the available height of the scrollview and the maxHeight to infinity
                    .frame(minHeight: proxy.size.height, maxHeight: .infinity)
                }
            }
        }
        .interactiveDismissDisabled(overlay.enabled)
        .addLoadingOverlay(overlay)
        .navigationTitle(advancedMode ? Text("Add Account (advanced)") : Text("Welcome"))
        .navigationBarTitleDisplayMode(advancedMode ? .inline : .large)
        .onDisappear {
            UITableView.appearance().tableHeaderView = nil      //why that??
            
            guard let newAccountID = self.newAccountID, currentTimeout != nil || errorObserverEnabled else {
                return
            }
            DispatchQueue.main.async {
                currentTimeout = nil // <- disable timeout when leaving ui
                errorObserverEnabled = false
                MLXMPPManager.sharedInstance().removeAccount(forAccountID: newAccountID)
                self.newAccountID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kXMPPError)).receive(on: RunLoop.main)) { notification in
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount.accountID.intValue == newAccountID.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on error
                        errorObserverEnabled = false
                        showLoginErrorAlert(errorMessage: errorMessage)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountID: newAccountID)
                        self.newAccountID = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMLSessionInitNotice)).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID {
                if(xmppAccount.accountID.intValue == newAccountID.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on successful connection
                        self.errorObserverEnabled = false
                        showLoadingOverlay(overlay, headline:"Loading contact list")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalUpdateBundleFetchStatus)).receive(on: RunLoop.main)) { notification in
            if let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountID : NSNumber = self.newAccountID {
                if(notificationAccountID.intValue == newAccountID.intValue) {
                    isLoadingOmemoBundles = true
                    showLoadingOverlay(
                        overlay, 
                        headline:"Loading omemo bundles",
                        description:"Loading omemo bundles: \(completed) / \(all)"
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalFinishedOmemoBundleFetch)).receive(on: RunLoop.main)) { notification in
            if let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber, let newAccountID : NSNumber = self.newAccountID {
                if(notificationAccountID.intValue == newAccountID.intValue && isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalFinishedCatchup)).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID {
                if(xmppAccount.accountID.intValue == newAccountID.intValue && !isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate)
    }
}

// MARK: - VELO: inviti (allineamento alla Velo Android 0.43.1, 19/11/2026)
//
// Un invito Velo e' il testo "velo:invite?v=1&d=<dominio>&o=<onion>&p=<impronte>&n=<nome>" con, se
// serve, t (token di registrazione XEP-0401/0445), u (nome utente gia' deciso) e i (chi invita).
// Arriva come link velo:, come link del sito (https://velochat.eu/invito.html#<invito>), da QR o
// incollato. Stesse regole di VeloServers/VeloFriendInvite su Android: mai una password dentro.

@objc class VeloInvite: NSObject {
    static let prefix = "velo:invite?"
    private static let domainPattern = "^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$"
    private static let onionPattern = "^[a-z2-7]{56}\\.onion$"
    private static let pinPattern = "^[A-Za-z0-9+/]{43}=$"
    private static let tokenPattern = "^[A-Za-z0-9_-]{8,128}$"
    static let namePattern = "^[a-z0-9._-]{1,64}$"

    @objc let domain: String
    @objc let onion: String
    let pins: [String]
    @objc let name: String
    @objc let token: String?
    @objc let user: String?
    @objc let inviter: String?

    private init(domain: String, onion: String, pins: [String], name: String, token: String?, user: String?, inviter: String?) {
        self.domain = domain
        self.onion = onion
        self.pins = pins
        self.name = name
        self.token = token
        self.user = user
        self.inviter = inviter
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    /// L'invito dentro un testo qualsiasi (un messaggio intero, il link del sito), come findInvite su Android.
    static func find(_ text: String?) -> String? {
        guard let text = text else { return nil }
        if let start = text.range(of: prefix) {
            let rest = text[start.lowerBound...]
            return String(rest.prefix(while: { !$0.isWhitespace }))
        }
        if let page = text.range(of: "/invito.html#") {
            let rest = text[page.upperBound...]
            return prefix + String(rest.prefix(while: { !$0.isWhitespace }))
        }
        return nil
    }

    /// Come URLDecoder.decode di Java: '+' diventa spazio, poi le sequenze %XX.
    private static func decode(_ value: String) -> String {
        let spaced = value.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    @objc static func parse(_ text: String?) -> VeloInvite? {
        guard let invite = find(text), invite.lowercased().hasPrefix(prefix) else { return nil }
        var params: [String: String] = [:]
        for part in invite.dropFirst(prefix.count).split(separator: "&") {
            guard let eq = part.firstIndex(of: "="), eq != part.startIndex else { continue }
            let key = String(part[part.startIndex..<eq])
            if params[key] == nil {
                params[key] = decode(String(part[part.index(after: eq)...])).trimmingCharacters(in: .whitespaces)
            }
        }
        guard params["v"] == "1" else { return nil }
        let domain = (params["d"] ?? "").lowercased()
        let onion = (params["o"] ?? "").lowercased()
        // un '+' non codificato in un'impronta diventa spazio quando si decodifica
        let pins = Array(Set((params["p"] ?? "").replacingOccurrences(of: " ", with: "+")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        guard matches(domain, domainPattern), matches(onion, onionPattern),
              !pins.isEmpty, pins.count <= 4, pins.allSatisfy({ matches($0, pinPattern) }) else { return nil }
        var name = (params["n"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(40).map(Character.init))
        if name.isEmpty { name = domain }
        let token = params["t"].flatMap { matches($0, tokenPattern) ? $0 : nil }
        let user = params["u"].flatMap { matches($0, namePattern) ? $0 : nil }
        let inviter = params["i"].flatMap { matches($0, namePattern) ? $0 : nil }
        return VeloInvite(domain: domain, onion: onion, pins: pins, name: name, token: token, user: user, inviter: inviter)
    }

    /// Gli otto caratteri che mostrano tutti i telefoni (e la pagina del sito): SHA-256("dominio|impronte ordinate").
    var shortCode: String {
        let digest = Array(SHA256.hash(data: Data((domain + "|" + pins.sorted().joined(separator: ",")).utf8)))
        let hex = digest.prefix(4).map { String(format: "%02X", $0) }.joined()
        return String(hex.prefix(4)) + "-" + String(hex.suffix(4))
    }

    /// Robustezza della password misurata come ejabberd (password_strength 64), uguale a VeloPasswordActivity.
    static func strength(_ password: String) -> Double {
        var lower = 0, digit = 0, upper = 0, other = 0, high = 0
        let bytes = Array(password.utf8)
        for c in bytes {
            if c >= 97 && c <= 122 { lower = 26 }
            else if c >= 48 && c <= 57 { digit = 9 }
            else if c >= 65 && c <= 90 { upper = 26 }
            else if c >= 33 && c <= 126 { other = 33 }
            else { high = 128 }
        }
        let pool = lower + digit + upper + other + high
        return bytes.isEmpty || pool == 0 ? 0 : Double(bytes.count) * log2(Double(pool))
    }
}

@objc class VeloInviteFlow: NSObject {
    private static func topController(_ base: UIViewController?) -> UIViewController? {
        var top = base
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    private static func rootController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.rootViewController
    }

    /// Da un link velo:, dal sito, da un QR o da "Incolla l'invito". Risponde false se il testo non e' un invito.
    @objc @discardableResult static func start(text: String?, from base: UIViewController?) -> Bool {
        guard let presenter = topController(base ?? rootController()) else { return false }
        guard let invite = VeloInvite.parse(text) else {
            let alert = UIAlertController(title: "Invito non valido", message: "Questo non è un invito Velo completo. Chiedi a chi ti ha invitato di mandarlo di nuovo.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            presenter.present(alert, animated: true)
            return false
        }
        let alert = UIAlertController(
            title: "Entrare in \(invite.name)?",
            message: "Velo si collegherà al server privato di questo gruppo, passando da Tor.\n\nControlla con chi ti ha dato l'invito che il suo telefono mostri lo stesso codice di verifica:\n\n\(invite.shortCode)\n\nSe è diverso, non continuare.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annulla", style: .cancel))
        alert.addAction(UIAlertAction(title: "Entra", style: .default) { _ in
            let host = UIHostingController(rootView: AnyView(EmptyView()))
            host.rootView = AnyView(NavigationStack { VeloInviteJoin(invite: invite, close: { done in
                host.dismiss(animated: true) {
                    // entrato: chiudo anche il benvenuto, se c'era
                    if done { VeloInviteFlow.rootController()?.dismiss(animated: true) }
                }
            }) })
            host.isModalInPresentation = true
            (VeloInviteFlow.topController(presenter) ?? presenter).present(host, animated: true)
        })
        presenter.present(alert, animated: true)
        return true
    }
}

/// Collegamento e registrazione per un invito (lo stato vive qui perche' la vista SwiftUI e' una struct).
class VeloInviteJoinModel: ObservableObject {
    @Published var working = false
    @Published var errorMessage: String? = nil
    @Published var done = false
    var registration: xmpp? = nil
    var accountID: NSNumber? = nil
    var timeout: DispatchWorkItem? = nil
    var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        registration?.disconnect(true)
    }
}

struct VeloInviteJoin: View {
    let invite: VeloInvite
    let close: (Bool) -> Void

    @State private var username: String
    @State private var password: String = ""
    @StateObject private var model = VeloInviteJoinModel()

    init(invite: VeloInvite, close: @escaping (Bool) -> Void) {
        self.invite = invite
        self.close = close
        self._username = State(wrappedValue: invite.user ?? "")
    }

    /// Un invito personale vale solo per quel nome: il server rifiuta gli altri (Android 0.43.1)
    private var nameLocked: Bool { invite.token != nil && invite.user != nil }
    private var registering: Bool { invite.token != nil }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            model.timeout?.cancel()
            model.observers.forEach { NotificationCenter.default.removeObserver($0) }
            model.observers = []
            if let id = model.accountID {
                MLXMPPManager.sharedInstance().removeAccount(forAccountID: id)
                model.accountID = nil
            }
            model.registration?.disconnect(true)
            model.registration = nil
            model.working = false
            model.errorMessage = message
        }
    }

    private func submit() {
        let name = username.lowercased().trimmingCharacters(in: .whitespaces)
        guard name.range(of: VeloInvite.namePattern, options: .regularExpression) != nil else {
            model.errorMessage = "Nome utente non valido: solo lettere minuscole, numeri, punto, trattino e trattino basso."
            return
        }
        if registering && VeloInvite.strength(password) < 64 {
            model.errorMessage = "Troppo debole: usa almeno 14 caratteri, meglio con maiuscole e numeri."
            return
        }
        if password.isEmpty {
            model.errorMessage = "Scrivi la password."
            return
        }
        if DataLayer.sharedInstance().doesAccountExistUser(name, andDomain: invite.domain) {
            model.errorMessage = "Questo account è già in Velo."
            return
        }
        model.errorMessage = nil
        model.working = true
        if registering {
            register(name)
        } else {
            login(name)
        }
    }

    private func register(_ name: String) {
        // VELO: anche la registrazione passa da Tor, sul .onion dell'invito (STARTTLS sulla 5222)
        let identity = MLXMPPIdentity(jid: "nothing@\(invite.domain)", password: "nothing", andResource: "VeloReg")
        let server = MLXMPPServer(host: invite.onion, andPort: 5222, andDirectTLS: false)
        let account = xmpp(server: server, andIdentity: identity, andAccountID: -1)
        model.registration = account
        let pw = password
        account.requestRegForm(withToken: invite.token, andCompletion: { captcha, hidden in
            if !captcha.isEmpty {
                return fail("Il server chiede un captcha: questo invito non si può usare da qui.")
            }
            account.registerUser(name, withPassword: pw, captcha: nil, andHiddenFields: hidden) { success, errorMessage in
                DispatchQueue.main.async {
                    account.disconnect(true)
                    model.registration = nil
                    if success {
                        login(name)
                    } else {
                        fail("Registrazione non riuscita: \(errorMessage ?? "l'invito potrebbe essere già usato o scaduto").")
                    }
                }
            }
        }, andErrorCompletion: { _, errorMessage in
            fail("Registrazione non riuscita: \(errorMessage ?? "l'invito potrebbe essere già usato o scaduto").")
        })
    }

    private func login(_ name: String) {
        // stesso collegamento della pagina di accesso: server .onion fisso, via Tor, niente PLAIN
        guard let id = MLXMPPManager.sharedInstance().login("\(name)@\(invite.domain)", password: password, hardcodedServer: invite.onion, hardcodedPort: "5222", forceDirectTLS: false, allowPlainAuth: false) else {
            return fail("Questo account è già in Velo.")
        }
        model.accountID = id
        let center = NotificationCenter.default
        model.observers.append(center.addObserver(forName: NSNotification.Name(kXMPPError), object: nil, queue: .main) { note in
            if let account = note.object as? xmpp, account.accountID.intValue == id.intValue {
                fail("Accesso non riuscito: \((note.userInfo?["message"] as? String) ?? "errore sconosciuto").")
            }
        })
        model.observers.append(center.addObserver(forName: NSNotification.Name(kMonalFinishedCatchup), object: nil, queue: .main) { note in
            guard let account = note.object as? xmpp, account.accountID.intValue == id.intValue, !model.done else { return }
            model.timeout?.cancel()
            model.done = true
            model.working = false
            model.accountID = nil   // l'account resta: e' entrato
            // come su Android: chi ha invitato diventa un contatto
            if let inviter = invite.inviter {
                let contact = MLContact.createContact(fromJid: "\(inviter)@\(invite.domain)", andAccountID: id)
                MLXMPPManager.sharedInstance().add(contact, withPreauthToken: nil)
            }
        })
        // la prima volta Tor puo' metterci a raggiungere un .onion mai visto
        let work = DispatchWorkItem { fail("Il server non risponde. Controlla la connessione e riprova tra poco.") }
        model.timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    var body: some View {
        Form {
            Section(footer: Text(registering ? "Almeno 14 caratteri, meglio con maiuscole e numeri. La scegli tu: nessun altro la conosce." : "Scrivi la password del tuo account.")) {
                TextField("Nome utente", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(nameLocked || model.working)
                    .foregroundColor(nameLocked ? .secondary : .primary)
                SecureField("Password", text: $password)
                    .disabled(model.working)
                    .onSubmit(submit)
            }
            if let message = model.errorMessage {
                Section { Text(message).foregroundColor(.red) }
            }
            Section {
                if model.done {
                    Text("Fatto: sei dentro.")
                    Button("Chiudi") { close(true) }
                } else if model.working {
                    HStack {
                        ProgressView()
                        Text(registering ? "Creo l'account via Tor…" : "Mi collego via Tor…").padding(.leading, 8)
                    }
                } else {
                    Button(registering ? "Crea l'account" : "Entra", action: submit)
                        .disabled(username.isEmpty || password.isEmpty)
                }
            }
            Section {
                Text("\(invite.name) · codice di verifica \(invite.shortCode)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(registering ? "Crea il tuo account" : "Entra in \(invite.name)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !model.done {
                    Button("Annulla") {
                        if model.working { fail("Annullato.") }
                        close(false)
                    }
                }
            }
        }
    }
}
