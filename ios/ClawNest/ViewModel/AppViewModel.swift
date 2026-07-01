import Foundation
import SwiftUI

enum ConnState { case disconnected, connecting, ready }

/// All app state + the connect/reconnect state machine. Mirrors android/.../ui/AppViewModel.kt,
/// trimmed to the iOS MVP (chat loop, personas, streaming, questions, proactive push, reconnect).
@MainActor
final class AppViewModel: ObservableObject {

    // Connection form
    @Published var host = ""
    @Published var sshUser = "root"
    @Published var sshPass = ""
    @Published var claudeKey = ""

    @Published var conn: ConnState = .disconnected
    @Published var showForm = false
    @Published var statusMsg = ""
    @Published var lang = "ru"
    @Published var busy = false
    @Published var useMock = false

    @Published var personas: [Persona] = []
    var models: [ModelInfo] = DEFAULT_MODELS
    @Published var personaModel: [String: String] = [:]
    @Published var audit: [AuditEntry] = []

    @Published var projects: [Proj] = [Proj(id: "default", name: "default")]
    @Published var currentProjectId = "default"
    @Published var currentPersonaId: String?

    // Structural changes (message added / thread rebuilt) bump this to re-render lists.
    @Published var threadTick = 0
    // Bumped on every streamed chunk to drive auto-scroll.
    @Published var scrollTick = 0

    private var threads: [String: [ChatMsg]] = [:]
    private var streamingMsg: ChatMsg?
    private var streamingKey: String?

    private var tunnel: Tunnel = MockTunnel()
    private var client: OpenClawClient?

    private var userDisconnected = false
    private var reconnecting = false
    private var connecting = false
    private var watchdog: Task<Void, Never>?

    var t: L { L(en: lang == "en") }

    init() { loadPrefs() }

    // MARK: prefs

    private func loadPrefs() {
        lang = Store.get("lang", "ru")
        host = Store.get("host", "")
        sshUser = Store.get("ssh_user", "root")
        sshPass = Store.get("ssh_pass", "")
        claudeKey = Store.get("claude_key", "")
        #if targetEnvironment(simulator)
        useMock = Store.get("use_mock", "1") == "1"
        #else
        useMock = Store.get("use_mock", "0") == "1"
        #endif
        if let raw = nonEmpty(Store.get("persona_models", "")),
           let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: String] {
            personaModel = obj
        }
    }

    private func saveCreds() {
        Store.put("host", host.trimmed)
        Store.put("ssh_user", sshUser.trimmed.isEmpty ? "root" : sshUser.trimmed)
        Store.put("ssh_pass", sshPass)
        Store.put("claude_key", claudeKey.trimmed)
    }

    func hasSavedCreds() -> Bool { !host.isEmpty && !sshPass.isEmpty }

    func setLang(_ code: String) { lang = code; Store.put("lang", code) }

    func setUseMock(_ v: Bool) { useMock = v; Store.put("use_mock", v ? "1" : "0") }

    private func savePersonaModels() {
        if let data = try? JSONSerialization.data(withJSONObject: personaModel),
           let s = String(data: data, encoding: .utf8) { Store.put("persona_models", s) }
    }

    // MARK: derived

    func persona(_ id: String?) -> Persona? { personas.first { $0.id == id } }
    func currentPersona() -> Persona? { persona(currentPersonaId) }
    func currentProj() -> Proj? { projects.first { $0.id == currentProjectId } }

    func modelFor(_ id: String?) -> String {
        personaModel[id ?? ""] ?? persona(id)?.defaultModel ?? "claude-opus-4-8"
    }
    func setModel(_ personaId: String, _ modelId: String) {
        personaModel[personaId] = modelId; savePersonaModels()
    }

    func threadKey() -> String { "\(currentProjectId):\(currentPersonaId ?? "")" }
    func messages(for key: String) -> [ChatMsg] { threads[key] ?? [] }
    func currentMessages() -> [ChatMsg] { messages(for: threadKey()) }

    func selectPersona(_ id: String) { currentPersonaId = id; threadTick += 1 }

    // MARK: connect

    private func makeTunnel() -> Tunnel { useMock ? MockTunnel() : SSHTunnel() }

    func connect() {
        if host.trimmed.isEmpty || sshPass.isEmpty {
            statusMsg = t.needCreds; showForm = true; return
        }
        if connecting { return }
        connecting = true
        userDisconnected = false
        showForm = false
        conn = .connecting
        statusMsg = t.stConnecting
        armWatchdog()
        Task { await doConnect() }
    }

    private func doConnect() async {
        client?.close(); client = nil
        tunnel.close()
        let tun = makeTunnel()
        tunnel = tun
        do {
            let ep = try await tun.connect(
                host: host.trimmed,
                user: sshUser.trimmed.isEmpty ? "root" : sshUser.trimmed,
                password: sshPass,
                claudeKey: claudeKey.trimmed
            )
            statusMsg = t.stAuth
            let c = OpenClawClient(channel: makeChannel(for: ep))
            wire(c)
            client = c
            c.connect { [weak c] in c?.auth(ep.token) }
        } catch {
            connecting = false
            cancelWatchdog()
            conn = .disconnected
            statusMsg = t.stConnectFail(error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func wire(_ c: OpenClawClient) {
        c.onEvent = { [weak self] ev in Task { @MainActor in self?.handle(ev) } }
        c.onDisconnected = { [weak self] r in Task { @MainActor in self?.onDisconnected(r) } }
        c.onClosed = { [weak self] r in Task { @MainActor in self?.onClosed(r) } }
    }

    private func armWatchdog() {
        cancelWatchdog()
        watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled || conn == .ready { return }
            connecting = false
            client?.close(); client = nil
            tunnel.close()
            conn = .disconnected
            statusMsg = t.stTimeout
            scheduleReconnect()
        }
    }
    private func cancelWatchdog() { watchdog?.cancel(); watchdog = nil }

    func editConnection() {
        userDisconnected = true; reconnecting = false; connecting = false
        cancelWatchdog()
        conn = .disconnected
        showForm = true
    }

    func autoConnect() {
        if conn == .disconnected && hasSavedCreds() && !userDisconnected { connect() }
    }
    func onResume() {
        if conn != .ready && !connecting && hasSavedCreds() && !userDisconnected { connect() }
    }

    private func scheduleReconnect() {
        if userDisconnected || reconnecting || !hasSavedCreds() { return }
        reconnecting = true
        statusMsg = t.stReconnecting
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            reconnecting = false
            if !userDisconnected && conn != .ready { connect() }
        }
    }

    func disconnect() {
        userDisconnected = true; reconnecting = false; connecting = false
        cancelWatchdog()
        client?.close(); client = nil
        tunnel.close()
        personas.removeAll()
        conn = .disconnected
        statusMsg = t.stDisconnected
    }

    private func abortStreaming(_ note: String) {
        if let m = streamingMsg { m.appendText("\n— \(note) —"); m.streaming = false }
        streamingMsg = nil
        busy = false
    }

    // MARK: chat actions

    private func appendMessage(_ msg: ChatMsg, to key: String) {
        threads[key, default: []].append(msg)
        threadTick += 1
    }

    func send(_ text: String) {
        guard let pid = currentPersonaId else { return }
        let body = text.trimmed
        if body.isEmpty || busy || conn != .ready { return }
        let tkey = threadKey()
        let um = userMsg(body)
        appendMessage(um, to: tkey)
        persistMessage(tkey, um)
        startTurn(pid: pid, text: body, tkey: tkey)
    }

    private func startTurn(pid: String, text: String, tkey: String) {
        let a = assistantMsg()
        appendMessage(a, to: tkey)
        streamingMsg = a
        streamingKey = tkey
        busy = true
        bump()
        let conv = (currentProj()?.shared == true) ? currentProjectId : tkey
        client?.prompt(persona: pid, model: modelFor(pid), conversationId: conv,
                       project: currentProjectId, text: text, cwd: currentProj()?.cwd)
    }

    private func persistMessage(_ key: String, _ msg: ChatMsg) {
        client?.saveMessage(conversationId: key, message: msg.toJson())
    }

    func answerQuestion(_ msg: ChatMsg, segIndex: Int, answer: String) {
        guard segIndex < msg.segs.count, !msg.segs[segIndex].answered, !answer.isEmpty, !busy else { return }
        msg.segs[segIndex].answered = true
        send(answer)
    }

    func interrupt() {
        client?.interrupt()
        if let m = streamingMsg {
            m.appendText("\n— \(t.interrupted) —"); m.streaming = false
            persistMessage(streamingKey ?? threadKey(), m)
        }
        streamingMsg = nil; streamingKey = nil; busy = false
    }

    func refreshAudit() { client?.getAudit(100) }

    private func bump() { scrollTick += 1 }

    // MARK: inbound events (already hopped to the main actor)

    private func handle(_ ev: ServerEvent) {
        switch ev {
        case .authOk(let models):
            if !models.isEmpty { self.models = models }
            client?.listPersonas()
            client?.getAudit(100)
            client?.getState()

        case .personas(let list):
            personas = list
            if currentPersonaId == nil || !list.contains(where: { $0.id == currentPersonaId }) {
                currentPersonaId = list.first?.id
            }
            conn = .ready
            statusMsg = t.stConnected
            reconnecting = false; connecting = false
            cancelWatchdog()
            showForm = false
            saveCreds()

        case .audit(let entries):
            audit = entries.reversed()

        case .state(let state):
            applyState(state)

        case .textDelta(let s):
            streamingMsg?.appendText(s); bump()

        case .thinkingDelta:
            break

        case .toolUse(let cmd):
            streamingMsg?.addTool(cmd); bump()

        case .toolResult(let exit, let out):
            streamingMsg?.fillTool(exit: exit, output: out); bump()

        case .turnEnd:
            if let m = streamingMsg {
                materializeFiles(m)
                m.streaming = false
                persistMessage(streamingKey ?? threadKey(), m)
            }
            streamingMsg = nil; streamingKey = nil
            busy = false
            client?.getAudit(100)

        case .interrupted:
            if let m = streamingMsg {
                m.appendText("\n— \(t.interrupted) —"); m.streaming = false
                persistMessage(streamingKey ?? threadKey(), m)
            }
            streamingMsg = nil; streamingKey = nil; busy = false

        case .question(let id, let qs):
            guard !qs.isEmpty else { break }
            let target = streamingMsg ?? currentMessages().last { $0.role == "assistant" }
            target?.segs.append(.question(id: id, questions: qs))
            bump()

        case .push(let conv, let text):
            handlePush(conv: conv, text: text)

        case .ok:
            break

        case .error(let message):
            if let m = streamingMsg {
                m.error = message; m.streaming = false
                persistMessage(streamingKey ?? threadKey(), m)
                streamingMsg = nil; streamingKey = nil
            }
            statusMsg = t.stError(message)
            busy = false

        case .unknown:
            break
        }
    }

    private func applyState(_ state: [String: Any]) {
        if let pj = state["projects"] as? [[String: Any]] {
            var byId: [String: Proj] = [:]
            var order: [String] = []
            for o in pj {
                guard let id = o["id"] as? String, !id.isEmpty else { continue }
                byId[id] = Proj(id: id, name: o["name"] as? String ?? id,
                                cwd: nonEmpty(o["cwd"] as? String ?? ""),
                                shared: o["shared"] as? Bool ?? false)
                order.append(id)
            }
            for p in projects where byId[p.id] == nil { byId[p.id] = p; order.append(p.id) }
            let merged = order.compactMap { byId[$0] }
            if !merged.isEmpty {
                projects = merged
                if !projects.contains(where: { $0.id == currentProjectId }) {
                    currentProjectId = projects.first!.id
                }
            }
        }
        if let convs = state["conversations"] as? [String: Any] {
            for (key, value) in convs {
                guard let arr = value as? [[String: Any]] else { continue }
                let existing = threads[key]?.count ?? 0
                if arr.count > existing {
                    threads[key] = arr.map { ChatMsg.fromJson($0) }
                }
            }
            threadTick += 1
        }
    }

    private func handlePush(conv: String, text: String) {
        guard !text.isEmpty else { return }
        let key = conv.isEmpty ? threadKey() : conv
        let last = threads[key]?.last
        let dup = last != nil && last!.role == "assistant" && last!.plain().trimmed == text.trimmed
        if !dup {
            appendMessage(ChatMsg(role: "assistant", segs: [.text(text)]), to: key)
            bump()
            if key != threadKey() {
                let name = persona(String(key.split(separator: ":").last ?? ""))?.name ?? t.agent
                Notifier.post(title: name, body: text)
            }
        }
    }

    /// Pull `[[FILE:/path]]` markers out of the finished reply into (non-image) attachments.
    private func materializeFiles(_ msg: ChatMsg) {
        var paths: [String] = []
        for i in msg.segs.indices where msg.segs[i].kind == .text {
            let text = msg.segs[i].text
            let range = NSRange(text.startIndex..., in: text)
            let matches = FILE_MARKER.matches(in: text, range: range)
            guard !matches.isEmpty else { continue }
            for match in matches {
                if let r = Range(match.range(at: 1), in: text) {
                    paths.append(String(text[r]).trimmed)
                }
            }
            let stripped = FILE_MARKER.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            msg.segs[i].text = stripped.trimmed
        }
        for path in paths where !path.isEmpty {
            let name = String(path.split(separator: "/").last ?? "file")
            msg.segs.append(.file(name: name, remotePath: path, isImage: isImageName(name)))
        }
    }

    // MARK: transport lifecycle

    private func onDisconnected(_ reason: String) {
        client = nil
        connecting = false
        cancelWatchdog()
        abortStreaming(t.linkLost)
        if !userDisconnected { conn = .connecting; scheduleReconnect() }
        else { conn = .disconnected }
    }
    private func onClosed(_ reason: String) { onDisconnected(reason) }
}

// MARK: - helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
