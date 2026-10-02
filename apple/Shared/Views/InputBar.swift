import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 输入栏：文字输入，输入为空时右侧是图片入口，否则是清空按钮。
struct InputBar: View {
    @ObservedObject var model: TranslatorModel
    var focused: FocusState<Bool>.Binding

    @State private var showFileImporter = false
    #if os(iOS)
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            TextField("输入单词、句子或一段话", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                // 输入时最多展开到 6 行，离开输入框后收起，把空间留给结果
                .lineLimit(focused.wrappedValue ? 1...6 : 1...2)
                .focused(focused)
                .onSubmit { model.submit() }
                .onChange(of: model.input) { model.inputChanged() }
                .padding(.vertical, 11)

            if model.input.isEmpty {
                imageButton
            } else {
                Button {
                    model.input = ""
                    focused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }

            Button {
                model.submit()
                #if os(iOS)
                focused.wrappedValue = false
                #endif
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.lxOnAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.lxAccent, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("翻译")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
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
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("拍照或选择图片翻译")
        #else
        Button { showFileImporter = true } label: {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("选择图片翻译，也可以直接 ⌘V 粘贴或拖入图片")
        .accessibilityLabel("选择图片翻译")
        #endif
    }
}
