import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Mac 的输入栏：回车翻译，⌥回车换行；加号选图片，⌘V 粘贴截图；方向和 AI 优化开关。
/// 平时最多占窗口 30%，粘贴长文时放宽到约一半。
struct ComposerView: View {
    @ObservedObject var controller: ConversationController
    let session: ChatSession
    var focused: FocusState<Bool>.Binding
    let screenHeight: CGFloat
    let onNeedAI: () -> Void

    @State private var showFiles = false

    private var isLong: Bool { controller.draft.count > 200 }

    private var maxLines: Int {
        let ratio: CGFloat = isLong ? 0.5 : 0.3
        return min(30, max(3, Int((screenHeight * ratio - 70) / 21)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isLong {
                Text("已输入 \(controller.draft.count) 个字符 · ⌥↩ 换行")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.top, 8)
            }
            TextField("输入单词、句子或一段话，回车翻译", text: $controller.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...maxLines)
                .focused(focused)
                .onSubmit { controller.send() }
                .padding(.horizontal, 12)
                .padding(.top, isLong ? 2 : 12)
                .padding(.bottom, 4)

            HStack(spacing: 6) {
                Menu {
                    Button("选择图片…（可多选）", systemImage: "photo.on.rectangle") { showFiles = true }
                    Button("粘贴剪贴板", systemImage: "doc.on.clipboard") { paste() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("添加图片：也可以 ⌘V 粘贴截图，或把图片拖进来")
                .accessibilityLabel("添加图片或粘贴")

                Button { controller.cycleDirection() } label: {
                    chip(directionLabel, systemName: "arrow.left.arrow.right", on: controller.direction != .auto)
                }
                .buttonStyle(.plain)
                .help("翻译方向，点按切换")

                Button {
                    if !session.aiEnabled, !AISettings.shared.isConfigured {
                        onNeedAI()
                    }
                    controller.setAI(!session.aiEnabled)
                } label: {
                    chip("AI 优化", systemName: "sparkles", on: session.aiEnabled, ai: true)
                }
                .buttonStyle(.plain)
                .help("这个会话里翻译后自动用 AI 优化")
                .accessibilityValue(session.aiEnabled ? "开" : "关")

                Spacer(minLength: 0)

                Button {
                    controller.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.lxOnAccent)
                        .frame(width: 32, height: 32)
                        .background(controller.draft.trimmed.isEmpty ? Color.secondary.opacity(0.4) : Color.lxAccent, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(controller.draft.trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("翻译")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let images = urls.compactMap { url -> NSImage? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return NSImage(contentsOf: url)
            }
            controller.sendImages(images)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in focused.wrappedValue = true }
    }

    private var directionLabel: String {
        switch controller.direction {
        case .auto: "自动"
        case .englishToChinese: "英→中"
        case .chineseToEnglish: "中→英"
        }
    }

    private func chip(_ title: String, systemName: String, on: Bool, ai: Bool = false) -> some View {
        Label(title, systemImage: systemName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(on ? (ai ? Color.lxAI : Color.lxAccent) : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(on ? (ai ? Color.lxAISoft : Color.lxAccentSoft) : Color.secondary.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
    }

    /// 剪贴板里是图片就作为一轮发送，是文字就放进输入框
    private func paste() {
        let board = NSPasteboard.general
        if let images = board.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty,
           (board.string(forType: .string)?.trimmed ?? "").isEmpty {
            controller.sendImages(images)
        } else if let text = board.string(forType: .string) {
            controller.draft += text
            focused.wrappedValue = true
        }
    }
}
