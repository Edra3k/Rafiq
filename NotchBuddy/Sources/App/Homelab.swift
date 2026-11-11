#if !APPSTORE
import AppKit
import Combine
import SwiftUI

// MARK: - Homelab: the "Server" pill (Proxmox, its VMs and labs, the local models)
// Reads Proxmox every 60 s while the pill is on (one timer, nothing when it is off), and
// Ollama's loaded models when its address is set. Actions (start, shut down, snapshot,
// back to a snapshot) use the action token and always ask first in an alert.
// The Hermes VM (Settings) gets a Proxmox snapshot before a risky approval: "Allow with a
// net" for an agent running on the server.

struct LoadedModel: Equatable {
    var name: String
    var vram: Int64
}

@MainActor
final class Homelab: ObservableObject {
    static let shared = Homelab()
    static let pillId = "integration_homelab"

    static let urlKey = "pveURL"
    static let tokenIdKey = "pveTokenId"
    static let actionTokenIdKey = "pveActionTokenId"
    static let hermesVMKey = "hermesVMID"
    static let secretKey = "pve-token"
    static let actionSecretKey = "pve-action-token"

    @Published private(set) var nodes: [PVENode] = []
    @Published private(set) var guests: [PVEGuest] = []
    @Published private(set) var storages: [PVEStorage] = []
    @Published private(set) var models: [LoadedModel] = []
    @Published private(set) var snapshots: [Int: [PVESnapshot]] = [:]
    @Published private(set) var busy = Set<Int>()
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdate: Date?

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var warnedStorage = Set<String>()

    private init() {
        AppState.shared.$activeIntegrations
            .map { $0.contains(Homelab.pillId) }
            .removeDuplicates()
            .sink { on in
                DispatchQueue.main.async { MainActor.assumeIsolated { Homelab.shared.setPolling(on) } }
            }
            .store(in: &cancellables)
    }

    func start() { _ = Self.shared }

    var isConfigured: Bool { client() != nil }
    var hasActionToken: Bool { client()?.actionAuth != nil }

    static var hermesVMID: Int { UserDefaults.standard.integer(forKey: hermesVMKey) }

    private func client() -> PVEClient? {
        let d = UserDefaults.standard
        guard let base = PVEParse.baseURL(d.string(forKey: Self.urlKey) ?? ""),
              let tokenId = d.string(forKey: Self.tokenIdKey), !tokenId.isEmpty,
              let secret = KeychainStore.shared.get(Self.secretKey), !secret.isEmpty else { return nil }
        var action: String?
        if let aid = d.string(forKey: Self.actionTokenIdKey), !aid.isEmpty,
           let asecret = KeychainStore.shared.get(Self.actionSecretKey), !asecret.isEmpty {
            action = PVEParse.authorization(tokenId: aid, secret: asecret)
        }
        let pinKey = "pveFingerprint-\(base.host ?? "")"
        return PVEClient(base: base, readAuth: PVEParse.authorization(tokenId: tokenId, secret: secret),
                         actionAuth: action, pinned: d.string(forKey: pinKey)) { fp in
            UserDefaults.standard.set(fp, forKey: pinKey)
        }
    }

    /// Settings: forget the remembered certificate (after reinstalling Proxmox).
    func forgetCertificate() {
        guard let host = PVEParse.baseURL(UserDefaults.standard.string(forKey: Self.urlKey) ?? "")?.host else { return }
        UserDefaults.standard.removeObject(forKey: "pveFingerprint-\(host)")
    }

    private func setPolling(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        refresh()
        let t = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Homelab.shared.refresh() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Reading

    func refresh() {
        guard let c = client() else {
            lastError = String(localized: "homelab.not-configured", defaultValue: "Set up the server in Settings → Integrations.")
            paint()
            return
        }
        Task {
            switch await c.get("/cluster/resources") {
            case .success(let data):
                let r = PVEParse.resources(data)
                nodes = r.nodes; guests = r.guests; storages = r.storages
                lastError = nil
                lastUpdate = Date()
                checkStorage()
            case .failure(let f):
                lastError = Self.describe(f)
            }
            await refreshModels()
            paint()
        }
    }

    private func refreshModels() async {
        let raw = AppState.shared.ollamaServerURL
        guard !raw.isEmpty, let url = URL(string: LocalChat.normaliseURL(raw) + "/api/ps") else { models = []; return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["models"] as? [[String: Any]] else { models = []; return }
        models = list.map { LoadedModel(name: $0["name"] as? String ?? "?", vram: ($0["size_vram"] as? NSNumber)?.int64Value ?? 0) }
    }

    func loadSnapshots(_ g: PVEGuest) {
        guard let c = client() else { return }
        Task {
            if case .success(let data) = await c.get("/nodes/\(g.node)/\(g.kind.rawValue)/\(g.vmid)/snapshot") {
                snapshots[g.vmid] = PVEParse.snapshots(data)
            }
        }
    }

    /// The pill's line: "7 running · CPU 38 %", or what went wrong.
    private func paint() {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        if let lastError {
            state.tasks[idx].steps = [lastError]
            state.tasks[idx].state = .error
            return
        }
        let running = guests.filter(\.running).count
        let cpu = nodes.first.map { Int(($0.cpu * 100).rounded()) } ?? 0
        state.tasks[idx].state = .idle
        state.tasks[idx].steps = [String(format: String(localized: "homelab.pill %lld %lld", defaultValue: "%lld running · CPU %lld %%"),
                                         Int64(running), Int64(cpu))]
    }

    private func checkStorage() {
        for s in storages where s.share >= 0.9 && !warnedStorage.contains(s.name) {
            warnedStorage.insert(s.name)
            AppState.shared.setPillBadge(.error, for: Self.pillId)
            DigestCenter.shared.show(Digest(
                kind: .server,
                title: String(format: String(localized: "homelab.storage.title %@ %lld", defaultValue: "Storage %@ is %lld %% full"),
                              s.name, Int64((s.share * 100).rounded())),
                subtitle: String(format: String(localized: "homelab.storage.free %@", defaultValue: "%@ left"),
                                 ByteCountFormatter.string(fromByteCount: max(0, s.total - s.used), countStyle: .file)),
                lines: [String(localized: "homelab.storage.advice", defaultValue: "Old backups and snapshots are the usual suspects.")]
            ))
        }
    }

    static func describe(_ f: PVEClient.Failure) -> String {
        switch f {
        case .notConfigured: return String(localized: "homelab.not-configured", defaultValue: "Set up the server in Settings → Integrations.")
        case .certificateChanged: return String(localized: "homelab.cert-changed", defaultValue: "The server's certificate changed: check it, then forget the old one in Settings.")
        case .unauthorized: return String(localized: "homelab.unauthorized", defaultValue: "Proxmox refused the token.")
        case .http(let c): return "Proxmox HTTP \(c)"
        case .network(let m): return m
        case .noActionToken: return String(localized: "homelab.no-action-token", defaultValue: "Actions need the second token (Settings).")
        }
    }

    // MARK: Actions (each asks first)

    enum Action { case start, shutdown, snapshot, rollback }

    func perform(_ action: Action, on g: PVEGuest) {
        guard let c = client(), !busy.contains(g.vmid) else { return }
        let latest = (snapshots[g.vmid] ?? []).first(where: \.byRafiq) ?? snapshots[g.vmid]?.first
        if action != .snapshot && action != .start {
            let alert = NSAlert()
            switch action {
            case .shutdown:
                alert.messageText = String(format: String(localized: "homelab.shutdown.title %@", defaultValue: "Shut down %@?"), g.name)
                alert.informativeText = String(localized: "homelab.shutdown.body", defaultValue: "Proxmox asks the guest to shut down cleanly.")
            default:
                guard let latest else { return }
                alert.messageText = String(format: String(localized: "homelab.rollback.title %@ %@", defaultValue: "Take %@ back to %@?"), g.name, latest.name)
                alert.informativeText = String(localized: "homelab.rollback.body", defaultValue: "Everything that changed in it since that snapshot is lost. It starts again afterwards if it was running.")
            }
            alert.addButton(withTitle: String(localized: "homelab.confirm", defaultValue: "Continue"))
            alert.addButton(withTitle: String(localized: "net.restore.cancel", defaultValue: "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        busy.insert(g.vmid)
        let base = "/nodes/\(g.node)/\(g.kind.rawValue)/\(g.vmid)"
        Task {
            var result: Result<Data, PVEClient.Failure>
            switch action {
            case .start: result = await c.post(base + "/status/start")
            case .shutdown: result = await c.post(base + "/status/shutdown")
            case .snapshot:
                result = await c.post(base + "/snapshot", form: ["snapname": PVEParse.snapshotName(at: Date()),
                                                                  "description": "Rafiq"])
            case .rollback:
                result = latest.map { _ in .failure(.notConfigured) } ?? .failure(.notConfigured)
                if let latest {
                    var form: [String: String] = [:]
                    if g.kind == .qemu, g.running { form["start"] = "1" }
                    result = await c.post(base + "/snapshot/\(latest.name)/rollback", form: form)
                }
            }
            busy.remove(g.vmid)
            switch result {
            case .success:
                SoundEngine.shared.play(action == .rollback ? "proud" : "pop")
                // Proxmox works on it in the background: read again shortly.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                refresh()
                loadSnapshots(g)
            case .failure(let f):
                lastError = Self.describe(f)
                SoundEngine.shared.play("error")
                paint()
            }
        }
    }

    /// Before a risky approval from Hermes on the server: a snapshot of its VM.
    /// Calls `done(true)` once Proxmox accepted the snapshot task.
    func snapshotHermesVM(_ done: @escaping @MainActor (Bool) -> Void) {
        let vmid = Self.hermesVMID
        guard vmid > 0, let c = client(), c.actionAuth != nil else { done(false); return }
        Task {
            if guests.isEmpty, case .success(let data) = await c.get("/cluster/resources") {
                guests = PVEParse.resources(data).guests
            }
            guard let g = guests.first(where: { $0.vmid == vmid }) else { done(false); return }
            let r = await c.post("/nodes/\(g.node)/\(g.kind.rawValue)/\(g.vmid)/snapshot",
                                 form: ["snapname": PVEParse.snapshotName(at: Date()), "description": "Rafiq net"])
            if case .success = r { done(true) } else { done(false) }
        }
    }

    var canNetHermes: Bool { Self.hermesVMID > 0 && hasActionToken }
}

// MARK: - The pill's card

struct HomelabCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var lab = Homelab.shared
    @ObservedObject private var link = ServerLink.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#E57000")).frame(width: 7, height: 7)
                Text(verbatim: lab.nodes.first.map { "Proxmox · \($0.name)" } ?? "Proxmox")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 2)
                tunnelDot
            }
            if let error = lab.lastError {
                Text(verbatim: error).font(.system(size: 10.5)).foregroundColor(Color(hex: "#F5A524")).lineLimit(2)
            } else if let node = lab.nodes.first {
                bar(String(localized: "homelab.cpu", defaultValue: "CPU"), node.cpu)
                bar(String(localized: "homelab.mem", defaultValue: "Memory"), node.maxMem > 0 ? Double(node.mem) / Double(node.maxMem) : 0)
                if let worst = lab.storages.max(by: { $0.share < $1.share }) {
                    bar(String(localized: "homelab.disk", defaultValue: "Storage"), worst.share)
                }
            }
            HStack(spacing: 5) {
                Text(verbatim: String(format: String(localized: "homelab.running %lld", defaultValue: "%lld running"),
                                      Int64(lab.guests.filter(\.running).count)))
                if let m = lab.models.first {
                    Text(verbatim: "· \(m.name)").lineLimit(1)
                }
                Spacer(minLength: 2)
                Button(String(localized: "homelab.open", defaultValue: "VMs and labs")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .homelab }
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: "#E8B64A"))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Color(hex: "#9CA1AA"))
        }
        .padding(.leading, 108)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var tunnelDot: some View {
        let (color, text): (String, String) = {
            switch link.tunnel {
            case .up: return ("#34D399", String(localized: "homelab.tunnel.up", defaultValue: "tunnel"))
            case .connecting: return ("#F5A524", String(localized: "homelab.tunnel.connecting", defaultValue: "connecting"))
            case .failed: return ("#F4505E", String(localized: "homelab.tunnel.down", defaultValue: "tunnel down"))
            case .off: return ("#5F646D", "")
            }
        }()
        if !text.isEmpty {
            HStack(spacing: 3) {
                Circle().fill(Color(hex: color)).frame(width: 5, height: 5)
                Text(verbatim: text).font(.system(size: 9.5, weight: .semibold)).foregroundColor(Color(hex: color))
            }
        }
    }

    private func bar(_ label: String, _ v: Double) -> some View {
        let color = v >= 0.9 ? "#F4505E" : v >= 0.7 ? "#F5A524" : "#34D399"
        return HStack(spacing: 6) {
            Text(verbatim: label).font(.system(size: 9.5)).foregroundColor(Color(hex: "#8E939C")).frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color(hex: color)).frame(width: geo.size.width * min(1, max(0, v)))
                }
            }
            .frame(height: 4)
            Text(verbatim: "\(Int((v * 100).rounded())) %").font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                .foregroundColor(Color(hex: v >= 0.9 ? "#F4505E" : "#C0C4CC")).frame(width: 34, alignment: .trailing)
        }
    }
}

// MARK: - VMs and labs (open island view)

struct HomelabView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var lab = Homelab.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "homelab.open", defaultValue: "VMs and labs"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !lab.hasActionToken {
                        Text(String(localized: "homelab.read-only", defaultValue: "read only"))
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                    }
                    Button(action: { withAnimation { state.view = .overview } }) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "#6B7079"))
                            .frame(width: 18, height: 18).background(Color.white.opacity(0.06)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(lab.guests) { g in row(g) }
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .onAppear { lab.refresh(); lab.guests.filter(\.isLab).forEach { lab.loadSnapshots($0) } }
    }

    private func row(_ g: PVEGuest) -> some View {
        let snap = (lab.snapshots[g.vmid] ?? []).first
        return HStack(spacing: 8) {
            Circle().fill(Color(hex: g.running ? "#34D399" : "#5F646D")).frame(width: 7, height: 7)
            Text(verbatim: g.name.isEmpty ? "\(g.vmid)" : g.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color(hex: g.running ? "#F5F6F8" : "#8E939C"))
                .lineLimit(1)
            Text(verbatim: "\(g.vmid)\(g.kind == .lxc ? " · CT" : "")\(g.isLab ? " · lab" : "")")
                .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
            if g.vmid == Homelab.hermesVMID {
                Text(verbatim: "Hermes").font(.system(size: 9.5, weight: .semibold)).foregroundColor(Color(hex: "#C084FC"))
            }
            Spacer(minLength: 4)
            if let snap, let t = snap.time {
                Text(verbatim: "◷ " + DateFormatter.localizedString(from: t, dateStyle: .none, timeStyle: .short))
                    .font(.system(size: 9.5, weight: .semibold)).foregroundColor(Color(hex: "#E8B64A"))
            }
            if lab.busy.contains(g.vmid) {
                ProgressView().controlSize(.mini)
            } else if lab.hasActionToken {
                if g.running {
                    small(String(localized: "homelab.snapshot", defaultValue: "Snapshot")) { lab.perform(.snapshot, on: g) }
                    if snap != nil { small(String(localized: "homelab.rollback", defaultValue: "Back")) { lab.perform(.rollback, on: g) } }
                    small(String(localized: "homelab.shutdown", defaultValue: "Stop")) { lab.perform(.shutdown, on: g) }
                } else {
                    small(String(localized: "homelab.start", defaultValue: "Start")) { lab.perform(.start, on: g) }
                }
            }
        }
        .padding(.vertical, 5)
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
        .onAppear { if snap == nil, g.isLab || g.vmid == Homelab.hermesVMID { lab.loadSnapshots(g) } }
    }

    private func small(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "#2A2C31")))
                .foregroundColor(Color(hex: "#E8E9EC"))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct HomelabSettings: View {
    @AppStorage(ServerLink.hostKey) private var host = ""
    @AppStorage(ServerLink.tunnelKey) private var tunnel = false
    @AppStorage(ServerLink.watchKey) private var watch = true
    @AppStorage(Homelab.urlKey) private var pveURL = ""
    @AppStorage(Homelab.tokenIdKey) private var tokenId = ""
    @AppStorage(Homelab.actionTokenIdKey) private var actionTokenId = ""
    @AppStorage(Homelab.hermesVMKey) private var hermesVM = 0
    @State private var secret = ""
    @State private var actionSecret = ""
    @ObservedObject private var link = ServerLink.shared
    @ObservedObject private var lab = Homelab.shared

    var body: some View {
        GroupBox(String(localized: "homelab.settings.title", defaultValue: "Home server")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "homelab.settings.ssh", defaultValue: "SSH: the host as in ~/.ssh/config (keys only, through WireGuard or Tailscale)."))
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField(String("pve-hermes"), text: $host).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Toggle(String(localized: "homelab.settings.tunnel", defaultValue: "Keep the tunnel open (agents on the server in the notch)"), isOn: $tunnel)
                    .onChange(of: tunnel) { _, _ in ServerLink.shared.applySettings() }
                Toggle(String(localized: "homelab.settings.watch", defaultValue: "Watch SSH logins and open ports"), isOn: $watch)
                    .onChange(of: watch) { _, _ in ServerLink.shared.applySettings() }
                HStack {
                    Button(String(localized: "homelab.settings.install", defaultValue: "Install the relay and the Hermes plugin on the server…")) {
                        ServerLink.shared.installOnServer()
                    }
                    .disabled(host.isEmpty || link.installing)
                    if link.installing { ProgressView().controlSize(.small) }
                }
                ForEach(Array(link.installLog.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                }
                Divider()
                Text(String(localized: "homelab.settings.pve", defaultValue: "Proxmox: address and API tokens (Datacenter → Permissions → API Tokens). A read-only token for the card; a second one, optional, for start, stop and snapshots."))
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField(String("10.8.0.2:8006"), text: $pveURL).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                HStack {
                    TextField(String("rafiq@pve!read"), text: $tokenId).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    SecureField(String(localized: "homelab.settings.secret", defaultValue: "Secret"), text: $secret).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .onSubmit { save(secret, Homelab.secretKey) }
                }
                HStack {
                    TextField(String("rafiq@pve!act"), text: $actionTokenId).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    SecureField(String(localized: "homelab.settings.secret", defaultValue: "Secret"), text: $actionSecret).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .onSubmit { save(actionSecret, Homelab.actionSecretKey) }
                }
                HStack {
                    Text(String(localized: "homelab.settings.hermes-vm", defaultValue: "Hermes VM (ID)"))
                    TextField(String("104"), value: $hermesVM, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    Text(String(localized: "homelab.settings.hermes-vm.help", defaultValue: "snapshot before a risky approval"))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                HStack {
                    Button(String(localized: "homelab.settings.test", defaultValue: "Save and test")) {
                        save(secret, Homelab.secretKey); save(actionSecret, Homelab.actionSecretKey)
                        Homelab.shared.refresh()
                    }
                    Button(String(localized: "homelab.settings.forget-cert", defaultValue: "Forget the certificate")) { Homelab.shared.forgetCertificate() }
                    if let e = lab.lastError { Text(verbatim: e).font(.system(size: 11)).foregroundColor(.orange) }
                    else if lab.lastUpdate != nil { Text(verbatim: "✓").foregroundColor(.green) }
                }
            }
            .padding(6)
        }
    }

    /// Secrets go to the Keychain only; the field empties itself once saved.
    private func save(_ value: String, _ key: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        KeychainStore.shared.set(key, value: v)
        if key == Homelab.secretKey { secret = "" } else { actionSecret = "" }
    }
}
#endif
