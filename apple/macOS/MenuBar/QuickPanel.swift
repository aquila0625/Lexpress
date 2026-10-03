import AppKit
import SwiftUI
import Translation

/// 菜单栏快捷翻译的小窗：不打开主窗口，就地显示译文。
@MainActor
final class QuickPanelModel: ObservableObject {
    enum Origin: String {
        case input = "输入"
        case selection = "选中文字"
        case clipboard = "剪贴板"
        case screenshot = "截图"
        case recognize = "截图识字"
    }

    @Published var source = ""
    @Published var image: NSImage?
    @Published var origin: Origin = .input
    @Published var translation: String?
    @Published var entry: WordEntry?
    @Published var working = false
    @Published var message: String?
    /// 固定后点别处也不关
    @Published var pinned = false
    /// 变化时让输入框获得焦点
    @Published var focusRequest = 0
    /// 程序改写原文时加一，让输入框重建：正在编辑的输入框不会显示从外面写进来的文字
    @Published private(set) var sourceRevision = 0

    let controller: ConversationController
    /// 交给主窗口的会话继续看（完整词条、AI 优化、写回复）
    var openInMainWindow: () -> Void = {}
    private var task: Task<Void, Never>?

    init(controller: ConversationController) {
        self.controller = controller
    }

    /// 空白小窗，等用户输入
    func startInput() {
        task?.cancel()
        origin = .input
        source = ""
        sourceRevision += 1
        image = nil
        reset()
        focusRequest += 1
    }

    func translate(text: String, origin: Origin) {
        task?.cancel()
        self.origin = origin
        source = text
        sourceRevision += 1
        image = nil
        retranslate()
    }

    /// 按当前输入框里的文字重新翻译（用户改了原文之后回车）
    func retranslate() {
        let text = source.trimmed
        task?.cancel()
        reset()
        guard !text.isEmpty else { return }
        task = Task { await perform(text) }
    }

    /// 先在本机识别图片里的文字。onlyRecognize 时识别完就复制文字，不翻译
    func translate(image: NSImage, origin: Origin) {
        task?.cancel()
        self.origin = origin
        self.image = image
        source = ""
        sourceRevision += 1
        reset()
        working = true
        task = Task {
            let text: String
            do {
                text = try await ImageText.recognize(image).trimmed
            } catch {
                log.error("image recognition failed: \(error.localizedDescription, privacy: .public)")
                text = ""
            }
            guard !Task.isCancelled else { return }
            log.info("image: recognized \(text.count, privacy: .public) chars from \(origin.rawValue, privacy: .public)")
            guard !text.isEmpty else {
                working = false
                message = origin != .clipboard && !ScreenCapture.hasPermission
                    ? "没有识别到文字。如果截到的只有桌面背景，请在“系统设置 › 隐私与安全性 › 屏幕与系统录音”里允许 Q-Translator，然后重新打开它。"
                    : "图片里没有识别到文字。"
                return
            }
            source = text
            sourceRevision += 1
            if origin == .recognize {
                Clipboard.copy(text)
                ClipboardWatcher.markOwnWrite()
                working = false
                message = "已识别并复制到剪贴板。需要翻译就按回车。"
            } else {
                await perform(text)
            }
        }
    }

    func openInConversation() {
        if let image, source.isEmpty || origin == .screenshot || origin == .recognize || origin == .clipboard {
            controller.sendImages([image])
        } else if !source.trimmed.isEmpty {
            controller.draft = source.trimmed
            controller.send()
        }
        openInMainWindow()
    }

    /// 可以复制的结果：译文，或单词的释义汇总
    var resultText: String? {
        if let translation { return translation }
        guard let entry else { return nil }
        return entry.definitions.map(\.text).joined(separator: "\n")
    }

    private func reset() {
        translation = nil
        entry = nil
        message = nil
        working = false
    }

    private func perform(_ text: String) async {
        working = true
        if isWordLike(text), let found = try? await Youdao.lookup(text).entry, !found.definitions.isEmpty {
            guard !Task.isCancelled else { return }
            entry = found
        } else {
            let result = await controller.quickTranslate(text)
            guard !Task.isCancelled else { return }
            translation = result.map { Self.matchLineFormatting(source: text, translation: $0) }
            if result == nil { message = "翻译失败，请检查网络后重试。" }
        }
        working = false
        log.info("quick panel: \(self.origin.rawValue, privacy: .public) \(text.count, privacy: .public) chars, word \(self.entry != nil, privacy: .public), translated \(self.translation != nil, privacy: .public)")
    }

    /// 译文保持原文的排版：段落和空行本来就按行对应，这里再把每行开头的缩进、
    /// 列表符号（- • * 等）和编号（1. 1、 (1) a) 等）补回去，机器翻译常把它们弄丢或改掉。
    static func matchLineFormatting(source: String, translation: String) -> String {
        let sourceLines = source.components(separatedBy: "\n")
        let translatedLines = translation.components(separatedBy: "\n")
        // 行数对不上时说明翻译合并或拆分了段落，不硬套
        guard sourceLines.count == translatedLines.count else { return translation }
        return zip(sourceLines, translatedLines).map { original, translated in
            let (indent, marker) = lineStart(original)
            let body = translated.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return translated }
            if marker.isEmpty { return indent + body }
            // 译文已经自带了列表符号或编号，就保留它，只补缩进
            if !lineStart(body).marker.isEmpty { return indent + body }
            return indent + marker + body
        }.joined(separator: "\n")
    }

    private static let markerPattern = try! NSRegularExpression(
        pattern: #"^([ \t\u3000]*)((?:[-*•·▪◦‣–—]|\d{1,3}[.)、．]|[（(]\d{1,3}[)）]|[A-Za-z][.)])[ \t\u3000]*)?"#)

    /// 一行开头的缩进，以及缩进后面的列表符号或编号（连同后面的空格）
    private static func lineStart(_ line: String) -> (indent: String, marker: String) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = markerPattern.firstMatch(in: line, range: range) else { return ("", "") }
        func group(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        return (group(1), group(2))
    }

    private func isWordLike(_ text: String) -> Bool {
        if text.contains(where: { "\n,.!?;，。！？；".contains($0) }) { return false }
        if text.containsChinese { return text.count <= 8 }
        return text.count <= 40 && text.split(separator: " ").count <= 4
    }
}

struct QuickPanelView: View {
    @ObservedObject var model: QuickPanelModel
    @ObservedObject var translator: SystemTranslator
    @ObservedObject private var speaker = Speaker.shared
    let close: () -> Void

    @FocusState private var focused: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 110, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 8))
            }

            TextField(model.origin == .input ? "输入单词、句子或一段话，回车翻译" : "原文", text: $model.source, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { model.retranslate() }
                .id(model.sourceRevision)
                .padding(10)
                .background(Color.lxSurface, in: .rect(cornerRadius: 10))

            result

            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if model.resultText != nil { actions }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .tint(.lxAccent)
        // 主窗口关着时也要能用系统离线翻译
        .translationTask(translator.configuration) { session in
            await translator.run(session)
        }
        .onChange(of: model.focusRequest) { focused = true }
        .onChange(of: model.resultText) { copied = false }
        .onAppear { if model.origin == .input { focused = true } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(model.origin.rawValue, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.lxAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.lxAccentSoft, in: .capsule)
            Spacer()
            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(model.pinned ? "取消固定（点别处时自动关闭）" : "固定小窗（点别处时不关闭）")
            Button { model.openInConversation() } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("在主窗口的会话里打开：完整词条、AI 优化、写回复")
            .disabled(model.source.trimmed.isEmpty && model.image == nil)
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("关闭（Esc）")
        }
        .font(.system(size: 13))
    }

    private var icon: String {
        switch model.origin {
        case .input: "keyboard"
        case .selection: "text.cursor"
        case .clipboard: "doc.on.clipboard"
        case .screenshot: "camera.viewfinder"
        case .recognize: "text.viewfinder"
        }
    }

    @ViewBuilder
    private var result: some View {
        if model.working {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.source.isEmpty ? "正在识别文字…" : "正在翻译…").font(.callout).foregroundStyle(.secondary)
            }
        } else if let entry = model.entry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.word).font(.system(size: 22, weight: .semibold, design: entry.isChinese ? .default : .serif))
                    if entry.isChinese {
                        pronunciation(label: "中", text: entry.pinyin ?? "", speech: .chinese(entry.word))
                    } else {
                        ForEach(entry.phonetics) { p in
                            pronunciation(label: p.label, text: "/\(p.ipa)/", speech: .english(entry.word, accent: p.accent))
                        }
                    }
                }
                ForEach(entry.definitions.prefix(6)) { d in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.text).font(.callout)
                        if let note = d.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .textSelection(.enabled)
                }
            }
        } else if let translation = model.translation {
            ScrollView {
                Text(translation)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pronunciation(label: String, text: String, speech: Speech) -> some View {
        Button { speaker.toggle(speech) } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(Color.lxAccent)
                Text(text).font(.callout).foregroundStyle(.secondary)
                Image(systemName: speaker.playing == speech ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.lxAccent)
            }
        }
        .buttonStyle(.borderless)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button {
                if let text = model.resultText {
                    Clipboard.copy(text)
                    ClipboardWatcher.markOwnWrite()
                }
                copied = true
            } label: {
                Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            if let text = model.resultText, model.entry == nil {
                let speech = Speech.text(text, isChinese: text.isMostlyChinese)
                Button { speaker.toggle(speech) } label: {
                    Label(speaker.playing == speech ? "停止" : "朗读",
                          systemImage: speaker.playing == speech ? "stop.fill" : "speaker.wave.2")
                }
            }
            Spacer()
            Text("⌥D 打开主窗口").font(.caption).foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

/// 浮在最上层的小窗。不激活 App，不会把主窗口一起带到前面；Esc 关闭。
final class QuickPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // 不用标题栏：标题栏会在内容上方多占一截高度。圆角和背景由 SwiftUI 画
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// 在某个屏幕坐标附近弹出：放在这一点的下方，超出屏幕就往回挪。
    /// takeFocus 为 false 时只显示不抢键盘，用户在别处打字不受影响
    func show(near point: NSPoint, takeFocus: Bool = true) {
        contentViewController?.view.layoutSubtreeIfNeeded()
        let size = frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 14)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 { origin.y = min(point.y + 14, visible.maxY - size.height - 8) }
            origin.y = min(origin.y, visible.maxY - size.height - 8)
        }
        setFrameOrigin(origin)
        if takeFocus {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }
}
