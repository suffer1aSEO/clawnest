import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if vm.personas.isEmpty {
                    Text(vm.t.noAgentPicked)
                        .foregroundStyle(Palette.textDim)
                        .padding(.top, 60)
                }
                ForEach(vm.personas) { p in
                    NavigationLink {
                        ChatView(persona: p).onAppear { vm.selectPersona(p.id) }
                    } label: {
                        AgentCard(persona: p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Palette.bg)
    }
}

struct AgentCard: View {
    @EnvironmentObject var vm: AppViewModel
    let persona: Persona

    private var accent: Color { personaColor(persona.themeColor) }
    private var modelLabel: String {
        let id = vm.modelFor(persona.id)
        return vm.models.first { $0.id == id }?.label ?? id
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 4, height: 40)
            Text(persona.emoji.isEmpty ? "🤖" : persona.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(persona.name).font(.headline).foregroundStyle(Palette.text)
                Text(modelLabel).font(.caption).foregroundStyle(Palette.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.textDim).font(.caption)
        }
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
    }
}
