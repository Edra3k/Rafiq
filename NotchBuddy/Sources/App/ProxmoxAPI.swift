import CryptoKit
import Foundation

// MARK: - Proxmox VE: the home server, its VMs and containers, their snapshots
// Talks to the Proxmox API (https://host:8006/api2/json) with API tokens kept in the
// Keychain: a read-only one for the card, a second one (optional) for the actions (start,
// stop, snapshot, rollback). Proxmox ships a self-signed certificate: the first connection
// remembers its SHA-256 fingerprint and later ones must match it (trust on first use);
// "Forget the certificate" in Settings starts over.
// Parsing is pure Foundation: tested by scripts/test-proxmox.sh.

struct PVENode: Equatable, Sendable {
    var name: String
    var online: Bool
    var cpu: Double          // 0…1
    var mem: Int64
    var maxMem: Int64
    var uptime: Int
}

struct PVEGuest: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case qemu, lxc }
    var vmid: Int
    var name: String
    var node: String
    var kind: Kind
    var running: Bool
    var mem: Int64
    var maxMem: Int64
    var cpu: Double
    var tags: [String]
    var template: Bool

    var id: Int { vmid }
    /// A lab: tagged "lab" in Proxmox (the card offers snapshots first).
    var isLab: Bool { tags.contains { $0.lowercased() == "lab" } }
}

struct PVEStorage: Equatable, Sendable {
    var name: String
    var node: String
    var used: Int64
    var total: Int64
    var share: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct PVESnapshot: Equatable, Sendable {
    var name: String
    var time: Date?
    var description: String
    /// Made by Rafiq ("rafiq-…"): the card's "Back to the snapshot" uses the newest of these.
    var byRafiq: Bool { name.hasPrefix("rafiq-") }
}

enum PVEParse {
    private static func data(_ json: Data) -> Any? {
        (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["data"]
    }

    private static func int64(_ v: Any?) -> Int64 {
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let n = Int64(s) { return n }
        return 0
    }

    /// GET /cluster/resources: nodes, guests (qemu, lxc) and storages in one call.
    static func resources(_ json: Data) -> (nodes: [PVENode], guests: [PVEGuest], storages: [PVEStorage]) {
        guard let items = data(json) as? [[String: Any]] else { return ([], [], []) }
        var nodes: [PVENode] = [], guests: [PVEGuest] = [], storages: [PVEStorage] = []
        for item in items {
            switch item["type"] as? String {
            case "node":
                nodes.append(PVENode(name: item["node"] as? String ?? "", online: (item["status"] as? String) == "online",
                                     cpu: (item["cpu"] as? NSNumber)?.doubleValue ?? 0,
                                     mem: int64(item["mem"]), maxMem: int64(item["maxmem"]),
                                     uptime: Int(int64(item["uptime"]))))
            case "qemu", "lxc":
                let tags = (item["tags"] as? String ?? "").split(whereSeparator: { ";, ".contains($0) }).map(String.init)
                guests.append(PVEGuest(vmid: Int(int64(item["vmid"])), name: item["name"] as? String ?? "",
                                       node: item["node"] as? String ?? "",
                                       kind: (item["type"] as? String) == "lxc" ? .lxc : .qemu,
                                       running: (item["status"] as? String) == "running",
                                       mem: int64(item["mem"]), maxMem: int64(item["maxmem"]),
                                       cpu: (item["cpu"] as? NSNumber)?.doubleValue ?? 0,
                                       tags: tags, template: int64(item["template"]) == 1))
            case "storage":
                storages.append(PVEStorage(name: item["storage"] as? String ?? "", node: item["node"] as? String ?? "",
                                           used: int64(item["disk"]), total: int64(item["maxdisk"])))
            default: break
            }
        }
        guests.sort { $0.vmid < $1.vmid }
        return (nodes, guests.filter { !$0.template }, storages)
    }

    /// GET /nodes/{node}/{qemu|lxc}/{vmid}/snapshot (the "current" entry left out), newest first.
    static func snapshots(_ json: Data) -> [PVESnapshot] {
        guard let items = data(json) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item["name"] as? String, name != "current" else { return nil }
            let t = int64(item["snaptime"])
            return PVESnapshot(name: name, time: t > 0 ? Date(timeIntervalSince1970: TimeInterval(t)) : nil,
                               description: item["description"] as? String ?? "")
        }
        .sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
    }

    /// A snapshot name Proxmox accepts: a letter first, then letters, digits, - and _.
    static func snapshotName(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "rafiq-" + f.string(from: date)
    }

    /// "PVEAPIToken=user@pam!rafiq=1234-…", from "user@pam!rafiq" and the secret.
    static func authorization(tokenId: String, secret: String) -> String {
        "PVEAPIToken=\(tokenId.trimmingCharacters(in: .whitespaces))=\(secret.trimmingCharacters(in: .whitespaces))"
    }

    /// "https://pve.home:8006" from what the user typed ("pve.home", "10.0.0.2:8006", a full URL).
    static func baseURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var c = URLComponents(string: s), c.host != nil else { return nil }
        c.scheme = "https"
        if c.port == nil { c.port = 8006 }
        c.path = ""
        return c.url
    }

    /// Lowercase hex SHA-256 of a certificate's DER bytes.
    static func fingerprint(_ der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Client

/// One request at a time is plenty: the card reads every 60 s while it is shown.
final class PVEClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    let base: URL
    let readAuth: String
    let actionAuth: String?
    /// The fingerprint trusted for this host; nil on the first connection (remembered then).
    private let pinned: String?
    private let onFirstFingerprint: @Sendable (String) -> Void
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    enum Failure: Error, Equatable {
        case notConfigured, certificateChanged, unauthorized, http(Int), network(String), noActionToken
    }

    init(base: URL, readAuth: String, actionAuth: String?, pinned: String?,
         onFirstFingerprint: @escaping @Sendable (String) -> Void) {
        self.base = base
        self.readAuth = readAuth
        self.actionAuth = actionAuth
        self.pinned = pinned
        self.onFirstFingerprint = onFirstFingerprint
    }

    private var certificateMismatch = false

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let fp = PVEParse.fingerprint(SecCertificateCopyData(leaf) as Data)
        if let pinned {
            if fp == pinned {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                certificateMismatch = true
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            onFirstFingerprint(fp)
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    func get(_ path: String) async -> Result<Data, Failure> {
        await send(path, method: "GET", auth: readAuth, form: nil)
    }

    func post(_ path: String, form: [String: String] = [:]) async -> Result<Data, Failure> {
        guard let actionAuth else { return .failure(.noActionToken) }
        return await send(path, method: "POST", auth: actionAuth, form: form)
    }

    private func send(_ path: String, method: String, auth: String, form: [String: String]?) async -> Result<Data, Failure> {
        guard let url = URL(string: "/api2/json" + path, relativeTo: base) else { return .failure(.notConfigured) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        if let form, method == "POST" {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var c = URLComponents()
            c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = (c.percentEncodedQuery ?? "").data(using: .utf8)
        }
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return .failure(.unauthorized) }
            guard (200..<300).contains(code) else { return .failure(.http(code)) }
            return .success(data)
        } catch {
            if certificateMismatch { return .failure(.certificateChanged) }
            return .failure(.network(error.localizedDescription))
        }
    }
}
