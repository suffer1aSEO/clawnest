import Foundation

/// Where the agent WebSocket lives after the tunnel is up, plus its auth token.
struct AgentEndpoint {
    let wsURL: String   // e.g. ws://127.0.0.1:<localPort>/   (or mock://… in the simulator)
    let token: String
}

/// Establishes the encrypted path to the agent and exposes file transfer.
/// Real impl = SSHTunnel (Citadel); simulator impl = MockTunnel.
protocol Tunnel: AnyObject {
    func connect(host: String, user: String, password: String, claudeKey: String) async throws -> AgentEndpoint
    func uploadFile(localPath: String, remotePath: String) async throws
    func downloadFile(remotePath: String, to localURL: URL) async throws
    func close()
}

/// A bidirectional text WebSocket. `OpenClawClient` sits on top and speaks the JSON protocol.
protocol WSChannel: AnyObject {
    func connect(onOpen: @escaping () -> Void,
                 onText: @escaping (String) -> Void,
                 onClose: @escaping (String) -> Void,
                 onFailure: @escaping (String) -> Void)
    func send(_ text: String)
    func close()
}

/// Picks the right channel for an endpoint. `mock://` → in-memory script; otherwise a real socket.
func makeChannel(for endpoint: AgentEndpoint) -> WSChannel {
    if endpoint.wsURL.hasPrefix("mock") { return MockWSChannel() }
    return URLSessionWSChannel(url: endpoint.wsURL)
}

// MARK: - Mock (lets the whole app run in the Simulator with no server)

final class MockTunnel: Tunnel {
    func connect(host: String, user: String, password: String, claudeKey: String) async throws -> AgentEndpoint {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return AgentEndpoint(wsURL: "mock://local", token: "mock-token")
    }
    func uploadFile(localPath: String, remotePath: String) async throws {}
    func downloadFile(remotePath: String, to localURL: URL) async throws {}
    func close() {}
}

/// Scripts a believable session: auth_ok → personas → state, and streams a canned reply to
/// every prompt so the UI can be exercised end-to-end without a VPS.
final class MockWSChannel: WSChannel {
    private var onText: ((String) -> Void)?
    private var closed = false

    func connect(onOpen: @escaping () -> Void, onText: @escaping (String) -> Void,
                 onClose: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        self.onText = onText
        DispatchQueue.main.async { onOpen() }
    }

    func send(_ text: String) {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "auth":
            emit(["type": "auth_ok", "models": DEFAULT_MODELS.map { ["id": $0.id, "label": $0.label] }])
        case "list_personas":
            emit(["type": "personas", "personas": [
                ["id": "programmer", "name": "Programmer", "emoji": "🧑‍💻", "theme_color": "#22c55e", "default_model": "claude-opus-4-8"],
                ["id": "sysadmin", "name": "Sysadmin", "emoji": "🛠", "theme_color": "#3b82f6", "default_model": "claude-sonnet-4-6"],
                ["id": "hacker", "name": "Hacker", "emoji": "🕶", "theme_color": "#8a63d2", "default_model": "claude-opus-4-8"],
            ]])
        case "get_state":
            emit(["type": "state", "projects": [["id": "default", "name": "default"]], "conversations": [:]])
        case "get_audit":
            emit(["type": "audit", "entries": []])
        case "prompt":
            streamReply(to: obj["text"] as? String ?? "")
        default:
            emit(["type": "ok"])
        }
    }

    func close() { closed = true }

    private func streamReply(to text: String) {
        let reply = "You said: “\(text)”. This is the mock agent — build on your Mac and connect a real VPS to talk to Claude."
        var delay = 0.15
        for word in reply.split(separator: " ") {
            after(delay) { self.emit(["type": "text_delta", "text": String(word) + " "]) }
            delay += 0.06
        }
        after(delay) { self.emit(["type": "turn_end", "usage": ["output_tokens": reply.count / 4]]) }
    }

    private func emit(_ dict: [String: Any]) {
        guard !closed,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { self.onText?(s) }
    }
    private func after(_ s: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: block)
    }
}
