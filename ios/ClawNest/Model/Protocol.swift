import Foundation

// Domain models — mirror android/.../Models.kt

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let label: String
}

struct AuditEntry: Identifiable, Hashable {
    let id = UUID()
    let ts: Double
    let persona: String
    let command: String
    let exitCode: Int
}

struct Persona: Identifiable, Hashable {
    let id: String
    var name: String
    var emoji: String = ""
    var defaultModel: String? = nil
    var themeColor: String? = nil
    var allowedTools: [String] = []
    var systemPrompt: String = ""
    var allTools: Bool = false
}

/// A project: stable `id` keys the conversation/context; `name` is the renamable label.
struct Proj: Identifiable, Hashable {
    let id: String
    var name: String
    var cwd: String? = nil
    var shared: Bool = false
}

let DEFAULT_MODELS: [ModelInfo] = [
    ModelInfo(id: "claude-opus-4-8", label: "Opus 4.8"),
    ModelInfo(id: "claude-sonnet-4-6", label: "Sonnet 4.6"),
    ModelInfo(id: "claude-haiku-4-5", label: "Haiku 4.5"),
]

// Interactive question (AskUserQuestion) — mirror ChatModel.kt
struct QOption: Hashable { let label: String; let description: String }
struct Q: Hashable {
    let question: String
    let header: String
    let multiSelect: Bool
    let options: [QOption]
}

/// One decoded inbound message from the agent. Mirrors OpenClawClient.handle() dispatch.
enum ServerEvent {
    case authOk(models: [ModelInfo])
    case personas([Persona])
    case textDelta(String)
    case thinkingDelta(String)
    case toolUse(command: String)
    case toolResult(exitCode: Int, output: String)
    case turnEnd(stopReason: String?, outputTokens: Int?)
    case interrupted
    case audit([AuditEntry])
    case state([String: Any])
    case question(id: String, questions: [Q])
    case push(conv: String, text: String)
    case ok
    case error(String)
    case unknown
}

/// Decodes the agent's JSON messages. Tolerant like the Kotlin org.json parser.
enum ProtocolDecoder {
    static func decode(_ text: String) -> ServerEvent? {
        guard let data = text.data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        switch m["type"] as? String {
        case "auth_ok":
            let arr = m["models"] as? [[String: Any]] ?? []
            let models = arr.compactMap { o -> ModelInfo? in
                guard let id = o["id"] as? String else { return nil }
                return ModelInfo(id: id, label: o["label"] as? String ?? id)
            }
            return .authOk(models: models)
        case "personas":
            let arr = m["personas"] as? [[String: Any]] ?? []
            let list = arr.compactMap { o -> Persona? in
                guard let id = o["id"] as? String else { return nil }
                let tools = (o["allowed_tools"] as? [Any])?.compactMap { $0 as? String } ?? []
                return Persona(
                    id: id,
                    name: o["name"] as? String ?? id,
                    emoji: o["emoji"] as? String ?? "",
                    defaultModel: o["default_model"] as? String,
                    themeColor: o["theme_color"] as? String,
                    allowedTools: tools,
                    systemPrompt: o["system_prompt"] as? String ?? "",
                    allTools: o["all_tools"] as? Bool ?? false
                )
            }
            return .personas(list)
        case "text_delta":     return .textDelta(m["text"] as? String ?? "")
        case "thinking_delta": return .thinkingDelta(m["text"] as? String ?? "")
        case "tool_use":       return .toolUse(command: m["command"] as? String ?? "")
        case "tool_result":
            return .toolResult(exitCode: intVal(m["exit_code"]) ?? 0, output: m["output"] as? String ?? "")
        case "turn_end":
            let usage = m["usage"] as? [String: Any]
            return .turnEnd(stopReason: m["stop_reason"] as? String, outputTokens: intVal(usage?["output_tokens"]))
        case "interrupted": return .interrupted
        case "audit":
            let arr = m["entries"] as? [[String: Any]] ?? []
            let entries = arr.map { o in
                AuditEntry(
                    ts: (o["ts"] as? Double) ?? 0,
                    persona: o["persona"] as? String ?? "?",
                    command: o["command"] as? String ?? "",
                    exitCode: intVal(o["exit_code"]) ?? 0
                )
            }
            return .audit(entries)
        case "state": return .state(m)
        case "question":
            return .question(id: m["id"] as? String ?? "", questions: parseQuestions(m["questions"] as? [Any] ?? []))
        case "push":
            return .push(conv: m["conv"] as? String ?? "", text: m["text"] as? String ?? "")
        case "ok":    return .ok
        case "error": return .error(m["message"] as? String ?? "error")
        default:      return .unknown
        }
    }

    static func parseQuestions(_ arr: [Any]) -> [Q] {
        arr.compactMap { el -> Q? in
            guard let o = el as? [String: Any] else { return nil }
            let opts = (o["options"] as? [[String: Any]] ?? []).map {
                QOption(label: $0["label"] as? String ?? "", description: $0["description"] as? String ?? "")
            }
            return Q(
                question: o["question"] as? String ?? "",
                header: o["header"] as? String ?? "",
                multiSelect: o["multiSelect"] as? Bool ?? false,
                options: opts
            )
        }
    }

    private static func intVal(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }
}

/// Serializes outbound frames to JSON strings. Mirrors OpenClawClient send() methods.
enum ClientFrame {
    static func json(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func auth(_ token: String) -> String { json(["type": "auth", "token": token]) }
    static func setApiKey(_ key: String) -> String { json(["type": "set_api_key", "key": key]) }
    static func listPersonas() -> String { json(["type": "list_personas"]) }
    static func getAudit(_ limit: Int = 100) -> String { json(["type": "get_audit", "limit": limit]) }
    static func getState() -> String { json(["type": "get_state"]) }
    static func interrupt() -> String { json(["type": "interrupt"]) }
    static func clearConversation(_ id: String) -> String {
        json(["type": "clear_conversation", "conversation_id": id])
    }
    static func renameProject(old: String, new: String) -> String {
        json(["type": "rename_project", "old": old, "new": new])
    }

    static func prompt(persona: String, model: String?, conversationId: String,
                       project: String, text: String, cwd: String?) -> String {
        var o: [String: Any] = [
            "type": "prompt", "persona": persona, "conversation_id": conversationId,
            "project": project, "text": text,
        ]
        if let model { o["model"] = model }
        if let cwd, !cwd.isEmpty { o["cwd"] = cwd }
        return json(o)
    }

    static func savePersona(_ p: Persona) -> String {
        var o: [String: Any] = [
            "id": p.id, "name": p.name, "emoji": p.emoji,
            "allowed_tools": p.allowedTools, "system_prompt": p.systemPrompt,
            "all_tools": p.allTools,
        ]
        if let m = p.defaultModel { o["default_model"] = m }
        if let c = p.themeColor { o["theme_color"] = c }
        return json(["type": "save_persona", "persona": o])
    }

    static func saveMessage(conversationId: String, message: [String: Any]) -> String {
        json(["type": "save_message", "conversation_id": conversationId, "message": message])
    }
    static func saveProjects(_ projects: [[String: Any]]) -> String {
        json(["type": "save_projects", "projects": projects])
    }
}
