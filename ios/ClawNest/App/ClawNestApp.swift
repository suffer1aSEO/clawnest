import SwiftUI

@main
struct ClawNestApp: App {
    @StateObject private var vm = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
                .tint(Palette.green)
                .onAppear {
                    Notifier.requestAuth()
                    vm.autoConnect()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { vm.onResume() }
                }
        }
    }
}
