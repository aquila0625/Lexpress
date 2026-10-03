import SwiftUI

/// 配色：白底、亮蓝主色，橙色只用于 AI 相关的内容。
extension Color {
    static let lxAccent = Color(light: 0x0B6BF0, dark: 0x62A8FF)
    static let lxOnAccent = Color(light: 0xFFFFFF, dark: 0x04142B)
    static let lxAccentSoft = Color(light: 0xDCEBFF, dark: 0x12305A)
    static let lxAI = Color(light: 0xB8430A, dark: 0xFFAE78)
    static let lxAISoft = Color(light: 0xFFEEDD, dark: 0x3A2210)
    static let lxBackground = Color(light: 0xFFFFFF, dark: 0x0B0E13)
    static let lxWash = Color(light: 0xE4F0FF, dark: 0x0F1B2E)
    static let lxSurface = Color(light: 0xF1F7FF, dark: 0x161B23)
    /// 会话里句子译文卡片的底色（浅薄荷绿），和蓝色的单词卡片、橙色的 AI 分开
    static let lxSentenceCard = Color(light: 0xEEF7F2, dark: 0x15221C)
    /// 会话里图片译文卡片的底色（中性浅灰）
    static let lxImageCard = Color(light: 0xF3F4F6, dark: 0x1A1D22)

    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

/// 页面背景：顶部一点很浅的蓝色，向下过渡到纯色
struct WashBackground: View {
    var body: some View {
        LinearGradient(colors: [.lxWash, .lxBackground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
            .ignoresSafeArea()
    }
}
