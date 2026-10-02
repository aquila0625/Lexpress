import SwiftUI
import Translation
import UniformTypeIdentifiers

/// 整个界面。窄屏（iPhone、窄窗口）单栏；宽屏（iPad、Mac 窗口）左侧多一栏历史。
struct RootView: View {
    @ObservedObject var model: TranslatorModel

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showReply = false
    @FocusState private var focused: Bool

    private let wideThreshold: CGFloat = 720
    private let twoColumnThreshold: CGFloat = 1000

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WashBackground()
                if geometry.size.width >= wideThreshold {
                    // 侧栏之外还够宽时，结果再分成左右两栏
                    wideLayout(twoColumns: geometry.size.width >= twoColumnThreshold)
                } else {
                    compactLayout
                }
            }
        }
        .tint(.lxAccent)
        .translationTask(model.config) { session in
            await model.runSession(session)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHistory) {
            HistoryView(model: model, asSheet: true)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReply) {
            if case .sentence(let result) = model.phase {
                ReplyView(received: result.source, receivedTranslation: result.translation)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first, provider.canLoadObject(ofClass: PlatformImage.self) else { return false }
            _ = provider.loadObject(ofClass: PlatformImage.self) { object, _ in
                guard let image = object as? PlatformImage else { return }
                Task { @MainActor in model.translateImage(image) }
            }
            return true
        }
        .onAppear { focused = true }
        #if os(iOS)
        // 点选历史或词组后收起键盘，让结果完整露出来
        .onChange(of: model.lookupCount) { focused = false }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            focused = true
            #if os(macOS)
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            #endif
        }
    }

    // MARK: 窄屏

    @ViewBuilder
    private var compactLayout: some View {
        #if os(iOS)
        // 手机：内容在上，输入栏悬浮在底部拇指区
        resultScroll(wide: false, showsRecent: true)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                HStack {
                    GlassIconButton(systemName: "clock", label: "历史与生词本") { showHistory = true }
                    Spacer()
                    DirectionPill(sourceIsChinese: model.input.containsChinese)
                    Spacer()
                    GlassIconButton(systemName: "slider.horizontal.3", label: "设置") { showSettings = true }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .safeAreaInset(edge: .bottom) {
                InputBar(model: model, focused: $focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        #else
        // Mac 的窄窗口：输入栏在上
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InputBar(model: model, focused: $focused)
                GlassIconButton(systemName: "clock", label: "历史与生词本") { showHistory = true }
                GlassIconButton(systemName: "slider.horizontal.3", label: "设置") { showSettings = true }
            }
            .padding(12)
            resultScroll(wide: false, showsRecent: true)
        }
        #endif
    }

    // MARK: 宽屏

    private func wideLayout(twoColumns: Bool) -> some View {
        HStack(spacing: 0) {
            HistoryView(model: model, asSheet: false)
                .frame(width: 280)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .padding(.leading, 14)
                .padding(.vertical, 14)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    InputBar(model: model, focused: $focused)
                    DirectionPill(sourceIsChinese: model.input.containsChinese)
                    GlassIconButton(systemName: "slider.horizontal.3", label: "设置") { showSettings = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)
                resultScroll(wide: twoColumns)
            }
        }
    }

    private func resultScroll(wide: Bool, showsRecent: Bool = false) -> some View {
        ScrollView {
            ResultContent(model: model, wide: wide, showsRecent: showsRecent,
                          onNeedAI: { showSettings = true },
                          onReply: { showReply = true })
                .padding(.horizontal, wide ? 24 : 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 输入栏下面的内容区：首页、加载中、词典结果、翻译结果
struct ResultContent: View {
    @ObservedObject var model: TranslatorModel
    let wide: Bool
    /// 没有侧栏的布局里，首页显示最近的记录
    let showsRecent: Bool
    let onNeedAI: () -> Void
    let onReply: () -> Void

    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let image = model.sourceImage {
                HStack(alignment: .top, spacing: 10) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(.rect(cornerRadius: 12))
                    Text("文字来自这张图片，在本机识别").font(.footnote).foregroundStyle(.secondary)
                }
            }

            switch model.phase {
            case .idle:
                home
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            case .word(let entry):
                WordView(entry: entry, model: model, wide: wide)
            case .sentence(let result):
                SentenceView(result: result, model: model, wide: wide, onNeedAI: onNeedAI, onReply: onReply)
            }
        }
    }

    /// 还没输入时：没有侧栏就显示最近的记录，有侧栏时只给一句提示
    @ViewBuilder
    private var home: some View {
        if showsRecent, !history.items.isEmpty {
            Block("最近") {
                VStack(spacing: 2) {
                    ForEach(history.items.prefix(8)) { item in
                        HistoryRow(item: item) { model.lookup(item.text) }
                    }
                }
                .padding(.horizontal, -12)
            }
        } else {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private var hint: String {
        #if os(macOS)
        "输入单词、句子或一段话\n⌥D 随时呼出 · ⌘V 可粘贴图片 · Esc 隐藏"
        #else
        "输入单词、句子或一段话\n也可以拍照或选一张图片来翻译"
        #endif
    }
}
