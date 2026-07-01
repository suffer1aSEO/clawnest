import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel

    private var showConnect: Bool {
        vm.showForm || (vm.conn != .ready && vm.personas.isEmpty)
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            if showConnect {
                ConnectView()
            } else {
                MainView()
            }
        }
    }
}

/// The signed-in app: agents list → chat, plus settings.
struct MainView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            AgentsView()
                .navigationTitle("ClawNest")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                    ToolbarItem(placement: .topBarLeading) { ConnBadge() }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .tint(Palette.green)
    }
}

/// Small connection-state dot + label in the nav bar.
struct ConnBadge: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            if vm.conn != .ready {
                Text(vm.statusMsg).font(.caption2).foregroundStyle(Palette.textDim).lineLimit(1)
            }
        }
    }
    private var color: Color {
        switch vm.conn {
        case .ready: return Palette.green
        case .connecting: return Palette.orange
        case .disconnected: return Palette.error
        }
    }
}
