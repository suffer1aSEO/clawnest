import Foundation

/// Marker the agent emits to hand a file/photo back to the user (see backend `_FILE_PROTOCOL`).
let FILE_MARKER = try! NSRegularExpression(pattern: #"\[\[FILE:([^\]]+)\]\]"#)

private let IMAGE_EXT = try! NSRegularExpression(
    pattern: #"(?i).*\.(png|jpe?g|gif|webp|bmp|heic|heif)$"#)

func isImageName(_ name: String) -> Bool {
    let r = NSRange(name.startIndex..., in: name)
    return IMAGE_EXT.firstMatch(in: name, range: r) != nil
}

/// A piece of an assistant/user message. Flat, mutable value type (mirrors ChatModel.kt's Seg
/// hierarchy). `kind` selects which fields are meaningful.
struct Seg: Identifiable, Hashable {
    enum Kind: String, Hashable { case text, tool, file, question }
    let id = UUID()
    var kind: Kind

    // text
    var text: String = ""
    // tool
    var command: String = ""
    var output: String = ""
    var exit: Int? = nil
    // file
    var fileName: String = ""
    var remotePath: String = ""
    var isImage: Bool = false
    var localPath: String? = nil
    var downloading: Bool = false
    var fileError: String? = nil
    // question
    var questionId: String = ""
    var questions: [Q] = []
    var answered: Bool = false

    static func text(_ s: String) -> Seg { Seg(kind: .text, text: s) }
    static func tool(_ cmd: String) -> Seg { Seg(kind: .tool, command: cmd) }
    static func file(name: String, remotePath: String, isImage: Bool, localPath: String? = nil) -> Seg {
        var s = Seg(kind: .file); s.fileName = name; s.remotePath = remotePath
        s.isImage = isImage; s.localPath = localPath; return s
    }
    static func question(id: String, questions: [Q]) -> Seg {
        var s = Seg(kind: .question); s.questionId = id; s.questions = questions; return s
    }
}

/// One chat message. ObservableObject so streaming mutations re-render just this bubble.
final class ChatMsg: ObservableObject, Identifiable {
    let id = UUID()
    let role: String            // "user" | "assistant"
    @Published var segs: [Seg]
    @Published var streaming: Bool
    @Published var error: String?

    init(role: String, segs: [Seg] = [], streaming: Bool = false, error: String? = nil) {
        self.role = role; self.segs = segs; self.streaming = streaming; self.error = error
    }

    func appendText(_ s: String) {
        if var last = segs.last, last.kind == .text {
            last.text += s
            segs[segs.count - 1] = last
        } else {
            segs.append(.text(s))
        }
    }

    func addTool(_ command: String) { segs.append(.tool(command)) }

    func fillTool(exit: Int, output: String) {
        if let idx = segs.lastIndex(where: { $0.kind == .tool }) {
            segs[idx].exit = exit
            segs[idx].output = output
        }
    }

    /// Plain-text view (user bubble / dedupe of proactive pushes).
    func plain() -> String { segs.filter { $0.kind == .text }.map(\.text).joined() }

    // ---- history serialization (mirrors ChatMsg.toJson / chatMsgFromJson) ----

    func toJson() -> [String: Any] {
        var arr: [[String: Any]] = []
        for seg in segs {
            switch seg.kind {
            case .text:
                arr.append(["t": "text", "text": seg.text])
            case .tool:
                var o: [String: Any] = ["t": "tool", "command": seg.command,
                                        "output": String(seg.output.prefix(4000))]
                if let e = seg.exit { o["exit"] = e }
                arr.append(o)
            case .file:
                arr.append(["t": "file", "name": seg.fileName, "path": seg.remotePath, "image": seg.isImage])
            case .question:
                let joined = seg.questions.map { "❓ \($0.question)" }.joined(separator: "\n")
                arr.append(["t": "text", "text": joined])
            }
        }
        var m: [String: Any] = ["role": role, "segs": arr]
        if let error { m["error"] = error }
        return m
    }

    static func fromJson(_ o: [String: Any]) -> ChatMsg {
        let m = ChatMsg(role: o["role"] as? String ?? "assistant")
        let arr = o["segs"] as? [[String: Any]] ?? []
        for s in arr {
            switch s["t"] as? String {
            case "text": m.segs.append(.text(s["text"] as? String ?? ""))
            case "tool":
                var seg = Seg.tool(s["command"] as? String ?? "")
                seg.output = s["output"] as? String ?? ""
                if let e = s["exit"] as? Int { seg.exit = e }
                m.segs.append(seg)
            case "file":
                m.segs.append(.file(name: s["name"] as? String ?? "",
                                    remotePath: s["path"] as? String ?? "",
                                    isImage: s["image"] as? Bool ?? false))
            default: break
            }
        }
        m.streaming = false
        if let e = o["error"] as? String, !e.isEmpty { m.error = e }
        return m
    }
}

func userMsg(_ text: String) -> ChatMsg { ChatMsg(role: "user", segs: [.text(text)]) }
func assistantMsg() -> ChatMsg { ChatMsg(role: "assistant", streaming: true) }
