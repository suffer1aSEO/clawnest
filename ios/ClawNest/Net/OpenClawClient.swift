import Foundation

/// WebSocket over URLSession, pointed at the SSH-forwarded local port (ws://127.0.0.1:<port>/).
/// The bytes ride inside the SSH tunnel, so plaintext ws:// to loopback is fine.
final class URLSessionWSChannel: NSObject, WSChannel, URLSessionWebSocketDelegate {
    private let url: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var onOpen: (() -> Void)?
    private var onText: ((String) -> Void)?
    private var onClose: ((String) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var opened = false

    init(url: String) { self.url = url }

    func connect(onOpen: @escaping () -> Void, onText: @escaping (String) -> Void,
                 onClose: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        self.onOpen = onOpen; self.onText = onText; self.onClose = onClose; self.onFailure = onFailure
        guard let u = URL(string: url) else { onFailure("bad ws url"); return }
        // No read timeout: turns can stream for minutes. The server pings; URLSession pongs.
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 0
        let sess = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = sess
        let t = sess.webSocketTask(with: u)
        self.task = t
        t.resume()
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s): self.onText?(s)
                case .data(let d): if let s = String(data: d, encoding: .utf8) { self.onText?(s) }
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let err):
                self.onFailure?(err.localizedDescription)
            }
        }
    }

    func send(_ text: String) {
        task?.send(.string(text)) { [weak self] err in
            if let err { self?.onFailure?(err.localizedDescription) }
        }
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        opened = true
        onOpen?()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?(String(data: reason ?? Data(), encoding: .utf8) ?? "closed")
    }
}

/// Typed protocol client — mirrors android/.../OpenClawClient.kt. Wraps a WSChannel and turns
/// inbound JSON into ServerEvents. Callbacks arrive on background threads; the ViewModel hops
/// them to the main actor.
final class OpenClawClient {
    private let ch: WSChannel

    var onEvent: ((ServerEvent) -> Void)?
    var onDisconnected: ((String) -> Void)?
    var onClosed: ((String) -> Void)?

    init(channel: WSChannel) { self.ch = channel }

    func connect(onOpen: @escaping () -> Void) {
        ch.connect(
            onOpen: onOpen,
            onText: { [weak self] text in
                if let ev = ProtocolDecoder.decode(text) { self?.onEvent?(ev) }
                else { self?.onEvent?(.error("bad json from agent")) }
            },
            onClose: { [weak self] reason in self?.onClosed?(reason) },
            onFailure: { [weak self] reason in self?.onDisconnected?(reason) }
        )
    }

    // ---- outbound (mirror the Kotlin send() helpers) ----
    func auth(_ token: String) { ch.send(ClientFrame.auth(token)) }
    func setApiKey(_ key: String) { ch.send(ClientFrame.setApiKey(key)) }
    func listPersonas() { ch.send(ClientFrame.listPersonas()) }
    func getAudit(_ limit: Int = 100) { ch.send(ClientFrame.getAudit(limit)) }
    func getState() { ch.send(ClientFrame.getState()) }
    func interrupt() { ch.send(ClientFrame.interrupt()) }
    func clearConversation(_ id: String) { ch.send(ClientFrame.clearConversation(id)) }
    func savePersona(_ p: Persona) { ch.send(ClientFrame.savePersona(p)) }
    func saveMessage(conversationId: String, message: [String: Any]) {
        ch.send(ClientFrame.saveMessage(conversationId: conversationId, message: message))
    }
    func saveProjects(_ projects: [[String: Any]]) { ch.send(ClientFrame.saveProjects(projects)) }
    func prompt(persona: String, model: String?, conversationId: String,
                project: String, text: String, cwd: String?) {
        ch.send(ClientFrame.prompt(persona: persona, model: model, conversationId: conversationId,
                                   project: project, text: text, cwd: cwd))
    }

    func close() { ch.close() }
}
