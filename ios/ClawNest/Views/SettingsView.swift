import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(vm.t.language) {
                    Picker(vm.t.language, selection: Binding(
                        get: { vm.lang }, set: { vm.setLang($0) })) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(vm.lang == "en" ? "Demo mode (no server)" : "Демо-режим (без сервера)",
                           isOn: Binding(get: { vm.useMock }, set: { vm.setUseMock($0) }))
                }

                Section {
                    Button(role: .destructive) {
                        vm.disconnect(); dismiss()
                    } label: {
                        Text(vm.t.disconnect)
                    }
                }

                Section {
                    Text(vm.t.about).font(.footnote).foregroundStyle(Palette.textDim)
                }
            }
            .navigationTitle(vm.t.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(vm.lang == "en" ? "Done" : "Готово") { dismiss() }
                }
            }
        }
    }
}
