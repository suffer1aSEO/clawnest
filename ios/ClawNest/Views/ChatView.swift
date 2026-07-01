import SwiftUI

struct ChatView: View {
    @EnvironmentObject var vm: AppViewModel
    let persona: Persona
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var accent: Color { personaColor(persona.themeColor) }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(Palette.bg)
        .navigationTitle(persona.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { modelMenu }
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(vm.models) { m in
                Button {
                    vm.setModel(persona.id, m.id)
                } label: {
                    if vm.modelFor(persona.id) == m.id { Label(m.label, systemImage: "checkmark") }
                    else { Text(m.label) }
                }
            }
        } label: {
            let id = vm.modelFor(persona.id)
            Text(vm.models.first { $0.id == id }?.label ?? id)
                .font(.caption).foregroundStyle(accent)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if vm.currentMessages().isEmpty {
                        Text(vm.t.emptyChat)
                            .foregroundStyle(Palette.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                    ForEach(vm.currentMessages()) { msg in
                        MessageRow(msg: msg, accent: accent)
                            .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.scrollTick) { _ in scrollToBottom(proxy) }
            .onChange(of: vm.threadTick) { _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(vm.t.messageHint, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(Palette.text)
                .focused($inputFocused)

            if vm.busy {
                Button { vm.interrupt() } label: {
                    Image(systemName: "stop.fill").foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Palette.error).clipShape(Circle())
                }
            } else {
                Button {
                    let text = draft
                    draft = ""
                    vm.send(text)
                } label: {
                    Image(systemName: "arrow.up").foregroundStyle(.black)
                        .frame(width: 40, height: 40).background(accent).clipShape(Circle())
                }
                .disabled(draft.trimmed.isEmpty || vm.conn != .ready)
                .opacity(draft.trimmed.isEmpty || vm.conn != .ready ? 0.5 : 1)
            }
        }
        .padding(12)
        .background(Palette.bg)
        .overlay(Divider().background(Palette.border), alignment: .top)
    }
}

// MARK: - Message row

struct MessageRow: View {
    @ObservedObject var msg: ChatMsg
    let accent: Color

    var body: some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 40)
                bubble
            }
        } else {
            HStack {
                assistantBody
                Spacer(minLength: 40)
            }
        }
    }

    private var bubble: some View {
        Text(msg.plain())
            .foregroundStyle(Palette.text)
            .padding(12)
            .background(Palette.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(msg.segs.enumerated()), id: \.element.id) { idx, seg in
                SegView(msg: msg, index: idx, seg: seg, accent: accent)
            }
            if msg.streaming {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(accent)
                }
            }
            if let err = msg.error {
                Text(err).font(.footnote).foregroundStyle(Palette.error)
            }
        }
    }
}

// MARK: - Segment views

struct SegView: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject var msg: ChatMsg
    let index: Int
    let seg: Seg
    let accent: Color

    var body: some View {
        switch seg.kind {
        case .text:
            mdText(seg.text).foregroundStyle(Palette.text).textSelection(.enabled)
        case .tool:
            ToolBlock(seg: seg)
        case .file:
            FileChip(seg: seg)
        case .question:
            QuestionCard(msg: msg, index: index, seg: seg, accent: accent)
        }
    }

    private func mdText(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }
}

struct ToolBlock: View {
    let seg: Seg
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.caption2)
                Text(seg.command).font(.system(.caption, design: .monospaced)).lineLimit(2)
                Spacer()
                if let e = seg.exit {
                    Text("exit \(e)").font(.caption2)
                        .foregroundStyle(e == 0 ? Palette.green : Palette.error)
                }
            }
            .foregroundStyle(Palette.textDim)
            if !seg.output.isEmpty {
                Text(seg.output)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(12)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct FileChip: View {
    let seg: Seg
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: seg.isImage ? "photo" : "doc")
            Text(seg.fileName).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
    }
}

/// Interactive AskUserQuestion card. Single-select sends on tap; multi-select collects then Sends.
struct QuestionCard: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject var msg: ChatMsg
    let index: Int
    let seg: Seg
    let accent: Color
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(seg.questions.enumerated()), id: \.offset) { _, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.question).font(.subheadline.bold()).foregroundStyle(Palette.text)
                    ForEach(q.options, id: \.label) { opt in
                        Button {
                            tap(q, opt.label)
                        } label: {
                            HStack {
                                if q.multiSelect {
                                    Image(systemName: picked.contains(opt.label) ? "checkmark.square.fill" : "square")
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label).foregroundStyle(Palette.text)
                                    if !opt.description.isEmpty {
                                        Text(opt.description).font(.caption).foregroundStyle(Palette.textDim)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Palette.surfaceAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(seg.answered)
                    }
                }
            }
            if seg.questions.contains(where: { $0.multiSelect }) && !seg.answered {
                Button("OK") { vm.answerQuestion(msg, segIndex: index, answer: picked.joined(separator: ", ")) }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.4), lineWidth: 1))
        .opacity(seg.answered ? 0.5 : 1)
    }

    private func tap(_ q: Q, _ label: String) {
        if q.multiSelect {
            if picked.contains(label) { picked.remove(label) } else { picked.insert(label) }
        } else {
            vm.answerQuestion(msg, segIndex: index, answer: label)
        }
    }
}
