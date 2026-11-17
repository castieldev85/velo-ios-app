//
//  VeloStories.swift
//  Velo iOS — storie cifrate, compatibili con la Velo Android (urn:velo:story:0).
//
//  Una storia è una foto o un video mandato a ogni contatto scelto come un normale messaggio file
//  cifrato in OMEMO2 PQ, con dentro la busta <story id expires><caption/></story>. Non compare
//  nella chat: compare come cerchio sopra l'elenco delle chat e sparisce dopo 24 ore.
//  SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Dati della barra

final class VeloStoriesModel: ObservableObject {
    static let shared = VeloStoriesModel()

    struct Group: Identifiable {
        let id: String
        let title: String
        let avatar: UIImage?
        let stories: [VeloMessageRules.Story]
        let own: Bool
        let unseen: Bool
    }

    @Published var groups: [Group] = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        let names = [VeloMessageRules.storiesChangedNotification, VeloMessageRules.expiredNotification,
                     UIApplication.didBecomeActiveNotification.rawValue]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
        reload()
    }

    func reload() {
        let all = VeloMessageRules.activeStories()
        var result: [Group] = []

        // le nostre: una per storia (la stessa storia è un messaggio per ogni contatto)
        var ownById: [String: VeloMessageRules.Story] = [:]
        for s in all where !s.inbound {
            if let old = ownById[s.storyId], old.added <= s.added { continue }
            ownById[s.storyId] = s
        }
        let own = ownById.values.sorted { $0.added < $1.added }
        if !own.isEmpty {
            result.append(Group(id: "me", title: "La tua storia", avatar: nil, stories: own, own: true,
                                unseen: false))
        }

        // dei contatti: per chat, la più vecchia prima; prima la chat con la storia più nuova
        var byChat: [String: [VeloMessageRules.Story]] = [:]
        for s in all where s.inbound {
            byChat["\(s.account.stringValue)|\(s.buddy)", default: []].append(s)
        }
        var others: [Group] = []
        for (key, stories) in byChat {
            let sorted = stories.sorted { $0.added < $1.added }
            guard let first = sorted.first else { continue }
            let contact = MLContact.createContact(fromJid: first.buddy, andAccountID: first.account)
            others.append(Group(id: key, title: contact.contactDisplayName, avatar: contact.avatar,
                                stories: sorted, own: false,
                                unseen: sorted.contains { !VeloMessageRules.isStorySeen($0.key) }))
        }
        others.sort { ($0.stories.last?.added ?? .distantPast) > ($1.stories.last?.added ?? .distantPast) }
        // prima quelle ancora da vedere
        result += others.filter { $0.unseen } + others.filter { !$0.unseen }
        groups = result
    }
}

// MARK: - Barra sopra l'elenco delle chat

struct VeloStoriesBar: View {
    @ObservedObject var model = VeloStoriesModel.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                Button { VeloStoriesUI.compose() } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 58, height: 58)
                            Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundColor(.accentColor)
                        }
                        Text("Crea storia").font(.caption2).foregroundColor(.primary).lineLimit(1)
                    }
                    .frame(width: 68)
                }
                ForEach(model.groups) { group in
                    Button { VeloStoriesUI.open(group) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(group.unseen || group.own
                                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.29), Color(red: 1, green: 0.44, blue: 0.69), Color(red: 0.56, green: 0.48, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Color.gray.opacity(0.5)),
                                            lineWidth: 3)
                                    .frame(width: 62, height: 62)
                                if let avatar = group.avatar {
                                    Image(uiImage: avatar).resizable().scaledToFill()
                                        .frame(width: 54, height: 54).clipShape(Circle())
                                } else {
                                    Circle().fill(Color(red: 0x1F / 255.0, green: 0x25 / 255.0, blue: 0x57 / 255.0))
                                        .frame(width: 54, height: 54)
                                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                                }
                            }
                            Text(group.title).font(.caption2).foregroundColor(.primary).lineLimit(1)
                        }
                        .frame(width: 68)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 100)
    }
}

// MARK: - Aggancio da Objective-C e presentazione

@objc class VeloStoriesUI: NSObject {
    private static var host: UIHostingController<VeloStoriesBar>?

    /// La barra delle storie, da mettere come intestazione dell'elenco delle chat.
    @objc static func makeHeaderView(width: CGFloat) -> UIView {
        let controller = UIHostingController(rootView: VeloStoriesBar())
        host = controller
        controller.view.backgroundColor = .clear
        controller.view.frame = CGRect(x: 0, y: 0, width: max(width, 320), height: 100)
        controller.view.autoresizingMask = [.flexibleWidth]
        return controller.view
    }

    private static func present(_ controller: UIViewController) {
        guard let root = (UIApplication.shared.delegate as? MonalAppDelegate)?.window?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        controller.modalPresentationStyle = .fullScreen
        top.present(controller, animated: true)
    }

    static func open(_ group: VeloStoriesModel.Group) {
        var controller: UIViewController?
        controller = UIHostingController(rootView: VeloStoryViewer(group: group) {
            controller?.dismiss(animated: true)
            VeloStoriesModel.shared.reload()
        })
        if let controller { present(controller) }
    }

    static func compose() {
        var controller: UIViewController?
        controller = UIHostingController(rootView: VeloStoryComposer {
            controller?.dismiss(animated: true)
        })
        if let controller { present(controller) }
    }
}

// MARK: - Visore

struct VeloStoryViewer: View {
    let group: VeloStoriesModel.Group
    let close: () -> Void

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var videoCopy: URL?
    @State private var waiting = true
    @State private var confirmDelete = false
    private let photoSeconds = 5.0
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var story: VeloMessageRules.Story? {
        index < group.stories.count ? group.stories[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).disabled(true)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if waiting {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Scaricamento…").foregroundColor(.white.opacity(0.8))
                }
            }
            // tocchi: sinistra = indietro, destra = avanti
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { previous() }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
            }
            VStack {
                HStack(spacing: 4) {
                    ForEach(0..<group.stories.count, id: \.self) { i in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.35))
                                Capsule().fill(Color.white)
                                    .frame(width: geo.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                HStack {
                    Text(group.title).font(.headline).foregroundColor(.white)
                    if let story {
                        Text(HelperTools.formatLastInteraction(story.added)).font(.footnote).foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    if group.own {
                        Button { confirmDelete = true } label: {
                            Image(systemName: "trash").font(.title3).foregroundColor(.white).padding(8)
                        }
                    }
                    Button { finish() } label: {
                        Image(systemName: "xmark").font(.title3.weight(.semibold)).foregroundColor(.white).padding(8)
                    }
                }
                .padding(.horizontal, 12)
                Spacer()
                if let caption = story?.caption, !caption.isEmpty {
                    Text(caption)
                        .foregroundColor(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.45))
                }
            }
        }
        .onAppear { load() }
        .onDisappear { cleanup() }
        .onReceive(tick) { _ in step() }
        .confirmationDialog("Eliminare questa storia per tutti?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina per tutti", role: .destructive) { deleteOwnStory() }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func load() {
        cleanup()
        progress = 0
        waiting = true
        guard let story else { finish(); return }
        VeloMessageRules.markStorySeen(story.key)
        refreshFile()
    }

    /// Prende il file se è già scaricato, altrimenti chiede il controllo o lo scaricamento.
    private func refreshFile() {
        guard let story else { return }
        guard let message = DataLayer.sharedInstance().veloMessage(messageId: story.messageId, buddy: story.buddy, accountID: story.account),
              message.messageType == kMessageTypeFiletransfer else {
            next()          //cancellata nel frattempo
            return
        }
        let maybeInfo: MLFiletransferInfo? = message.fileInfo
        guard let info = maybeInfo else { return }
        let historyId = message.messageDBId
        switch info.downloadState {
        case .complete:
            guard let source = info.fileURL else { return }
            if info.isVideo {
                let ext = (info.mimeType ?? "").contains("quicktime") ? "mov" : "mp4"
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("velo-story-\(UUID().uuidString).\(ext)")
                guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else { return }
                videoCopy = copy
                let p = AVPlayer(url: copy)
                player = p
                p.play()
            } else {
                image = UIImage(contentsOfFile: source.path)
            }
            waiting = false
        case .headers:
            if !MLFiletransfer.isFileForHistoryId(inTransfer: historyId) {
                MLFiletransfer.downloadFile(forHistoryID: historyId)
            }
        default:
            if !MLFiletransfer.isFileForHistoryId(inTransfer: historyId) {
                MLFiletransfer.checkMimeTypeAndSize(forHistoryID: historyId)
            }
        }
    }

    private func step() {
        if waiting {
            //ogni mezzo secondo riguarda se il file è arrivato
            if Int(Date().timeIntervalSince1970 * 10) % 5 == 0 { refreshFile() }
            return
        }
        if let player, let item = player.currentItem {
            let duration = item.duration.seconds
            if duration.isFinite && duration > 0 {
                progress = min(1, player.currentTime().seconds / duration)
                if progress >= 0.999 { next() }
            }
        } else {
            progress += 0.1 / photoSeconds
            if progress >= 1 { next() }
        }
    }

    private func next() {
        if index + 1 < group.stories.count {
            index += 1
            load()
        } else {
            finish()
        }
    }

    private func previous() {
        if index > 0 { index -= 1 }
        load()
    }

    private func cleanup() {
        player?.pause()
        player = nil
        image = nil
        if let videoCopy { try? FileManager.default.removeItem(at: videoCopy) }
        videoCopy = nil
    }

    private func finish() {
        cleanup()
        close()
    }

    /// Elimina per tutti: richiamo cifrato a ogni contatto che l'ha ricevuta, poi via anche da qui.
    private func deleteOwnStory() {
        guard let story else { return }
        for s in VeloMessageRules.activeStories() where !s.inbound && s.storyId == story.storyId {
            if let message = DataLayer.sharedInstance().veloMessage(messageId: s.messageId, buddy: s.buddy, accountID: s.account),
               let account = message.chatContact.account {
                account.retractMessage(message)
            }
            //lo spazzino cancella messaggio e file entro un paio di secondi
            VeloMessageRules.registerExpiry(account: s.account, buddy: s.buddy, messageId: s.messageId, at: Date())
        }
        finish()
    }
}

// MARK: - Nuova storia

struct VeloStoryMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("velo-story-up-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

struct VeloStoryComposer: View {
    let close: () -> Void

    struct Recipient: Identifiable {
        let id: String
        let contact: MLContact
        var selected: Bool
    }

    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var loading = false
    @State private var caption = ""
    @State private var recipients: [Recipient] = []
    @State private var sending = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .any(of: [.images, .videos])) {
                        Label(image == nil && videoURL == nil ? "Scegli foto o video" : "Cambia foto o video", systemImage: "photo.on.rectangle")
                    }
                    if loading {
                        ProgressView()
                    } else if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                    } else if videoURL != nil {
                        Label("Video pronto", systemImage: "video")
                    }
                }
                Section(header: Text("Didascalia")) {
                    TextField("Scrivi qualcosa (facoltativo)", text: $caption)
                }
                Section(header: Text("Chi la vede"), footer: Text("Solo i contatti Velo con la cifratura post-quantistica. La storia sparisce dopo 24 ore.")) {
                    if recipients.isEmpty {
                        Text("Nessun contatto Velo disponibile").foregroundColor(.secondary)
                    }
                    ForEach($recipients) { $r in
                        Toggle(r.contact.contactDisplayName, isOn: $r.selected)
                    }
                }
                if let result {
                    Section { Text(result) }
                }
            }
            .navigationTitle("Nuova storia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { cleanupAndClose() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Pubblica") { publish() }
                            .disabled((image == nil && videoURL == nil) || !recipients.contains { $0.selected })
                    }
                }
            }
            .onAppear { loadRecipients() }
            .onChange(of: item) { _, newItem in loadMedia(newItem) }
        }
    }

    private func loadRecipients() {
        var list: [Recipient] = []
        for contact in DataLayer.sharedInstance().contactList() {
            guard !contact.isMuc, !contact.isSelf, let account = contact.account,
                  account.veloCanReceivePQ(contact.contactJid) else { continue }
            list.append(Recipient(id: "\(contact.accountID.stringValue)|\(contact.contactJid)", contact: contact, selected: true))
        }
        recipients = list.sorted { $0.contact.contactDisplayName.localizedCaseInsensitiveCompare($1.contact.contactDisplayName) == .orderedAscending }
    }

    private func loadMedia(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        loading = true
        image = nil
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        videoURL = nil
        let isVideo = newItem.supportedContentTypes.contains { $0.conforms(to: .movie) }
        Task {
            if isVideo {
                let movie = try? await newItem.loadTransferable(type: VeloStoryMovie.self)
                await MainActor.run { videoURL = movie?.url; loading = false }
            } else {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run { image = data.flatMap { UIImage(data: $0) }; loading = false }
            }
        }
    }

    /// Un file cifrato per ogni contatto, ognuno con la sua chiave (come la Velo Android).
    private func publish() {
        let chosen = recipients.filter { $0.selected }.map { $0.contact }
        let storyId = UUID().uuidString
        let expires = Date().addingTimeInterval(24 * 60 * 60)
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = image
        let video = videoURL
        sending = true
        Task {
            var sent = 0
            var failed = 0
            for contact in chosen {
                guard let account = contact.account else { failed += 1; continue }
                do {
                    var url: String, mimeType: String, size: NSNumber
                    if let photo {
                        (url, mimeType, size) = try await MLFiletransfer.uploadUIImage(photo, onAccount: account, withEncryption: true)
                    } else if let video {
                        (url, mimeType, size) = try await MLFiletransfer.uploadFile(video, onAccount: account, withEncryption: true)
                    } else {
                        break
                    }
                    let ok = await MainActor.run { () -> Bool in
                        VeloMessageRules.setPendingStory(account: account.accountID, jid: contact.contactJid, storyId: storyId, caption: text, expires: expires)
                        return MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: url, havingType: kMessageTypeFiletransfer, toContact: contact, isEncrypted: true, uploadInfo: ["mimeType": mimeType, "size": size]) != nil
                    }
                    if ok { sent += 1 } else { failed += 1 }
                } catch {
                    DDLogError("VELO: story upload for \(contact.contactJid) failed: \(error)")
                    failed += 1
                }
            }
            let summary = failed == 0 ? "Storia mandata a \(sent) contatti." : "Storia mandata a \(sent) contatti, non riuscita per \(failed)."
            await MainActor.run {
                sending = false
                if failed == 0 {
                    cleanupAndClose()
                } else {
                    result = summary
                }
            }
        }
    }

    private func cleanupAndClose() {
        if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
        close()
    }
}
