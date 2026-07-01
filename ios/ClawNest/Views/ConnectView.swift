import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if vm.hasSavedCreds() && !vm.showForm {
                    // Splash while auto-connecting with saved creds.
                    VStack(spacing: 16) {
                        ProgressView().tint(Palette.green)
                        Text(vm.statusMsg).foregroundStyle(Palette.textDim)
                        Button(vm.t.editConnection) { vm.editConnection() }
                            .buttonStyle(.bordered).tint(Palette.gray)
                    }
                    .padding(.top, 40)
                } else {
                    form
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 44)).foregroundStyle(Palette.green)
                .padding(.top, 40)
            Text("ClawNest").font(.largeTitle.bold()).foregroundStyle(Palette.text)
            Text(vm.t.about).font(.footnote).foregroundStyle(Palette.textDim)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            field(vm.t.serverIP, text: $vm.host, keyboard: .URL)
            field(vm.t.sshUser, text: $vm.sshUser)
            secureField(vm.t.sshPass, text: $vm.sshPass)
            field(vm.t.claudeKey, text: $vm.claudeKey, secure: false)

            Toggle(isOn: Binding(get: { vm.useMock }, set: { vm.setUseMock($0) })) {
                Text(vm.lang == "en" ? "Demo mode (no server)" : "Демо-режим (без сервера)")
                    .foregroundStyle(Palette.textDim).font(.subheadline)
            }
            .tint(Palette.green)

            if !vm.statusMsg.isEmpty {
                Text(vm.statusMsg).font(.footnote)
                    .foregroundStyle(vm.conn == .disconnected ? Palette.error : Palette.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: { vm.connect() }) {
                HStack {
                    if vm.conn == .connecting { ProgressView().tint(.black) }
                    Text(vm.t.connectBtn).bold()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .background(Palette.green).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(vm.conn == .connecting)
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.textDim)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Palette.text)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.textDim)
            SecureField("", text: text)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Palette.text)
        }
    }
}
