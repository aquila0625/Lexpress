import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 输入区：上面是多行输入框（内容多了在框内滚动），下面一行是图片、朗读、清空和翻译。
struct InputBar: View {
    @ObservedObject var model: TranslatorModel
    var focused: FocusState<Bool>.Binding
    /// 输入框最多展开到几行，由屏幕高度决定（整个输入区不超过屏幕的 30%）
    let maxLines: Int

    @ObservedObject private var speaker = Speaker.shared
    @State private var showFileImporter = false
    #if os(iOS)
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            TextField("输入单词、句子或一段话", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .lineLimit(3...max(3, maxLines))
                .focused(focused)
                .onSubmit { model.submit() }
                .onChange(of: model.input) { model.inputChanged() }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            HStack(spacing: 0) {
                imageButton
                if !model.input.trimmed.isEmpty {
                    let speech = Speech.text(model.input.trimmed, isChinese: model.sourceIsChinese(model.input))
                    iconButton(speaker.playing == speech ? "stop.fill" : "speaker.wave.2",
                               label: speaker.playing == speech ? "停止朗读" : "朗读原文") {
                        speaker.toggle(speech)
                    }
                }
                Spacer()
                if !model.input.isEmpty {
                    iconButton("xmark.circle.fill", label: "清空") {
                        model.input = ""
                        focused.wrappedValue = true
                    }
                }
                Button {
                    model.submit()
                    #if os(iOS)
                    focused.wrappedValue = false
                    #endif
                } label: {
                    Label("翻译", systemImage: "arrow.up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.lxOnAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Color.lxAccent, in: .capsule)
                        .frame(height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.bottom, 2)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let image = PlatformImage(contentsOfFile: url.path) { model.translateImage(image) }
        }
        #if os(iOS)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.translateImage(image)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { model.translateImage($0) }.ignoresSafeArea()
        }
        #endif
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var imageButton: some View {
        #if os(iOS)
        Menu {
            if CameraPicker.isAvailable {
                Button("拍照", systemImage: "camera") { showCamera = true }
            }
            Button("从相册选择", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
            Button("从文件选择", systemImage: "folder") { showFileImporter = true }
        } label: {
            Image(systemName: "camera")
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("拍照或选择图片翻译")
        #else
        iconButton("photo", label: "选择图片翻译") { showFileImporter = true }
            .help("选择图片翻译，也可以直接 ⌘V 粘贴或拖入图片")
        #endif
    }
}
