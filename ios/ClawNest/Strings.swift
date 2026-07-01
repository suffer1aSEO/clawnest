import Foundation

/// Minimal RU/EN string bundle for the iOS MVP (mirrors the subset of android/.../ui/Strings.kt
/// that the screens below use). `en` is driven by the persisted "lang" setting.
struct L {
    let en: Bool
    private func s(_ ru: String, _ eng: String) -> String { en ? eng : ru }

    // Connect screen
    var connectTitle: String { s("Подключение", "Connect") }
    var serverIP: String { s("IP сервера", "Server IP") }
    var sshUser: String { s("SSH-пользователь", "SSH user") }
    var sshPass: String { s("SSH-пароль", "SSH password") }
    var claudeKey: String { s("Ключ Claude (опц.)", "Claude key (optional)") }
    var connectBtn: String { s("Подключиться", "Connect") }
    var editConnection: String { s("Изменить данные", "Edit connection") }
    var needCreds: String { s("Введите IP и SSH-пароль", "Enter server IP and SSH password") }

    // Agents / chat
    var agents: String { s("Агенты", "Agents") }
    var agent: String { s("Агент", "Agent") }
    var settings: String { s("Настройки", "Settings") }
    var messageHint: String { s("Сообщение…", "Message…") }
    var send: String { s("Отправить", "Send") }
    var stop: String { s("Стоп", "Stop") }
    var interrupted: String { s("прервано", "interrupted") }
    var linkLost: String { s("связь потеряна", "link lost") }
    var thinking: String { s("думает…", "thinking…") }
    var noAgentPicked: String { s("Выберите агента", "Pick an agent") }
    var emptyChat: String { s("Начните диалог", "Start the conversation") }

    // Settings
    var language: String { s("Язык", "Language") }
    var disconnect: String { s("Отключиться", "Disconnect") }
    var about: String { s("ClawNest — карманный пульт к вашим ИИ-агентам на вашем VPS.",
                          "ClawNest — a pocket remote for your AI agents on your VPS.") }

    // Statuses
    var stConnecting: String { s("Подключение…", "Connecting…") }
    var stAuth: String { s("Авторизация…", "Authorizing…") }
    var stConnected: String { s("Подключено", "Connected") }
    var stDisconnected: String { s("Отключено", "Disconnected") }
    var stReconnecting: String { s("Переподключение…", "Reconnecting…") }
    var stTimeout: String { s("Таймаут подключения", "Connection timed out") }
    func stConnectFail(_ e: String?) -> String { s("Ошибка подключения: \(e ?? "?")", "Connect failed: \(e ?? "?")") }
    func stError(_ e: String) -> String { s("Ошибка: \(e)", "Error: \(e)") }
}
