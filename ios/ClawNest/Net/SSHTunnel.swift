import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Citadel

enum TunnelError: LocalizedError {
    case ssh(String)
    case provision(String)
    case forward(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .ssh(let s): return "SSH: \(s)"
        case .provision(let s): return "setup: \(s)"
        case .forward(let s): return "forward: \(s)"
        case .notImplemented(let s): return s
        }
    }
}

/// One SSH session does everything, exactly like android/.../SshLink.kt:
/// connect → run provision.sh (to ensure the agent is configured and read its token) →
/// open a local port-forward to the agent's WebSocket port. All agent traffic rides INSIDE
/// the SSH connection; the app then talks plain ws:// to 127.0.0.1:<forwarded port>.
///
/// ⚠️ Built against Citadel's classic async API (SSHClient.connect / executeCommand /
/// createDirectTCPIPChannel). If your resolved Citadel version differs, this file is the one
/// place to adjust — see README-ios.md. Cannot be compiled off a Mac with Xcode.
final class SSHTunnel: Tunnel {
    private var client: SSHClient?
    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    // Try 22 first, then 443 — many mobile/Wi-Fi networks block 22 but never 443.
    private let sshPorts = [22, 443]

    func connect(host: String, user: String, password: String, claudeKey: String) async throws -> AgentEndpoint {
        let client = try await connectSSH(host: host, user: user, password: password)
        self.client = client

        let result = try await runProvision(client: client, claudeKey: claudeKey)
        let agentHost = result["agent_host"] as? String ?? "10.13.37.1"
        let agentPort = (result["agent_port"] as? Int) ?? 8765
        guard let token = result["token"] as? String else {
            throw TunnelError.provision("no token in result")
        }

        let localPort = try await startForward(client: client, remoteHost: agentHost, remotePort: agentPort)
        return AgentEndpoint(wsURL: "ws://127.0.0.1:\(localPort)/", token: token)
    }

    // MARK: connect

    private func connectSSH(host: String, user: String, password: String) async throws -> SSHClient {
        var last: Error?
        for port in sshPorts {
            do {
                return try await SSHClient.connect(
                    host: host,
                    port: port,
                    authenticationMethod: .passwordBased(username: user, password: password),
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never
                )
            } catch {
                last = error
            }
        }
        throw TunnelError.ssh(last?.localizedDescription ?? "no connection (ports 22/443)")
    }

    // MARK: provision

    private func runProvision(client: SSHClient, claudeKey: String) async throws -> [String: Any] {
        var script = try Provision.script()
        script = script.replacingOccurrences(of: "__CLAUDE_KEY__", with: Provision.shEscape(claudeKey))
        // executeCommand has no stdin channel (unlike JSch's `bash -s`), so ship the whole
        // script base64-encoded as a single command argument and decode it server-side.
        let b64 = Data(script.utf8).base64EncodedString()
        let cmd = "echo \(b64) | base64 --decode | bash"

        let buffer = try await client.executeCommand(cmd, maxResponseSize: 8_000_000, mergeStreams: true)
        let out = String(buffer: buffer)

        let marker = "===OPENCLAW-RESULT==="
        guard let start = out.range(of: marker),
              let end = out.range(of: "===END==="),
              start.upperBound <= end.lowerBound else {
            throw TunnelError.provision(String(out.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let jsonStr = String(out[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonStr.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TunnelError.provision("bad result json")
        }
        return obj
    }

    // MARK: local port-forward

    private func startForward(client: SSHClient, remoteHost: String, remotePort: Int) async throws -> Int {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            // Read manually so no bytes are consumed before the SSH channel is wired up.
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { inbound in
                let promise = inbound.eventLoop.makePromise(of: Void.self)
                let originPort = inbound.remoteAddress?.port ?? 0
                Task {
                    do {
                        let origin = try SocketAddress(ipAddress: "127.0.0.1", port: originPort)
                        let outbound = try await client.createDirectTCPIPChannel(
                            using: SSHChannelType.DirectTCPIP(
                                targetHost: remoteHost,
                                targetPort: remotePort,
                                originatorAddress: origin
                            )
                        ) { channel in
                            channel.setOption(ChannelOptions.autoRead, value: false)
                        }
                        try await inbound.pipeline.addHandler(ForwardHandler(peer: outbound)).get()
                        try await outbound.pipeline.addHandler(ForwardHandler(peer: inbound)).get()
                        inbound.read()
                        outbound.read()
                        promise.succeed(())
                    } catch {
                        inbound.close(promise: nil)
                        promise.fail(error)
                    }
                }
                return promise.futureResult
            }

        let ch = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        self.serverChannel = ch
        guard let port = ch.localAddress?.port else {
            throw TunnelError.forward("no local port assigned")
        }
        return port
    }

    // MARK: SFTP (attachments — deferred in v1)

    func uploadFile(localPath: String, remotePath: String) async throws {
        throw TunnelError.notImplemented("file upload not implemented yet (see README-ios.md TODO)")
    }

    func downloadFile(remotePath: String, to localURL: URL) async throws {
        throw TunnelError.notImplemented("file download not implemented yet (see README-ios.md TODO)")
    }

    // MARK: teardown

    func close() {
        let client = self.client
        let serverChannel = self.serverChannel
        let group = self.group
        self.client = nil; self.serverChannel = nil; self.group = nil
        Task {
            try? await serverChannel?.close()
            try? await client?.close()
            try? await group?.shutdownGracefully()
        }
    }
}

/// Loads the provision.sh bundled with the app (identical to the Android asset).
enum Provision {
    static func script() throws -> String {
        guard let url = Bundle.main.url(forResource: "provision", withExtension: "sh"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw TunnelError.provision("provision.sh missing from app bundle")
        }
        return s
    }

    /// Escape a value to sit safely inside single quotes in bash.
    static func shEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}
