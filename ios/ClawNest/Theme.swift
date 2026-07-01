import SwiftUI

/// Dark palette — mirrors android/.../ui/Theme.kt so iOS matches the mockups.
enum Palette {
    static let bg = Color(hex: 0x0A0B0D)
    static let surface = Color(hex: 0x16181D)
    static let surfaceAlt = Color(hex: 0x1D2026)
    static let border = Color(hex: 0x2A2E36)
    static let text = Color(hex: 0xE7E9EE)
    static let textDim = Color(hex: 0x9AA0AA)
    static let userBubble = Color(hex: 0x20242C)
    static let error = Color(hex: 0xE5534B)

    // Persona accents
    static let green = Color(hex: 0x22C55E)
    static let purple = Color(hex: 0x8A63D2)
    static let orange = Color(hex: 0xE8833A)
    static let blue = Color(hex: 0x3B82F6)
    static let gray = Color(hex: 0xAAB0BA)
    static let pink = Color(hex: 0xEC4899)

    static let swatches: [Color] = [green, purple, orange, blue, gray, pink]
}

/// Resolve a persona's theme_color string (e.g. "#8a63d2") to a Color, with fallback.
func personaColor(_ hex: String?) -> Color {
    guard let hex, !hex.isEmpty else { return Palette.green }
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard let v = UInt64(s, radix: 16) else { return Palette.green }
    if s.count <= 6 { return Color(hex: v) }
    // 8-digit AARRGGBB
    let a = Double((v >> 24) & 0xFF) / 255
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

extension Color {
    /// From a 0xRRGGBB literal.
    init(hex: UInt64) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
