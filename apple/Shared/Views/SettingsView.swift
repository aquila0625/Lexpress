import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    @AppStorage(SettingsKey.accent) private var accent = 2
    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = false

    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("服务商", selection: $ai.provider) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    SecureField("API Key", text: $ai.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    if let url = ai.provider.signupURL {
                        Link("去 \(ai.provider.title) 注册并获取 API Key", destination: url)
                    }
                    if ai.provider == .custom {
                        TextField("接口地址，例如 https://api.openai.com/v1", text: $ai.baseURL)
                            .autocorrectionDisabled()
                    }
                    if !ai.provider.suggestedModels.isEmpty {
                        Picker("模型", selection: $ai.model) {
                            ForEach(ai.provider.modelGroups, id: \.title) { group in
                                Section(group.title) {
                                    ForEach(group.models, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            if !ai.provider.suggestedModels.contains(ai.model) {
                                Text(ai.model.isEmpty ? "未选择" : ai.model).tag(ai.model)
                            }
                        }
                    }
                    TextField("或手动填写模型名称", text: $ai.model)
                        .autocorrectionDisabled()
                    Toggle("AI 优化：翻译句子后自动优化译文", isOn: $ai.autoCalibrate)
                    Button {
                        test()
                    } label: {
                        HStack {
                            Text("测试连接")
                            if testing { ProgressView().controlSize(.small) }
                            Spacer()
                            if let testResult { Text(testResult).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(testing || !ai.isConfigured)
                } header: {
                    Text("AI 增强（可选）")
                } footer: {
                    Text("Lexpress 不提供 AI 额度，也不经过任何中间服务器：你自己在服务商那里注册，把 API Key 填在这里，费用由服务商向你收取。Key 只保存在本机钥匙串。注意 ChatGPT 的会员订阅不包含 API 额度，API Key 要在 OpenAI 开发者平台单独申请。不填也能使用词典、翻译、朗读和图片翻译。AI 用于优化句子翻译和帮你写回复；上面的开关关闭时不会自动优化，只有你点“AI 优化”才会运行。每次优化后会显示消耗的 token 数。")
                }

                Section("朗读") {
                    Picker("默认英文口音", selection: $accent) {
                        Text("英式").tag(1)
                        Text("美式").tag(2)
                    }
                    Toggle("查词后自动朗读", isOn: $autoSpeak)
                }

                Section {
                    LabeledContent("单词", value: "有道词典（在线）")
                    LabeledContent("句子和段落", value: "系统离线翻译，其次 MyMemory")
                    LabeledContent("图片文字", value: "本机识别，不上传")
                } header: {
                    Text("翻译来源")
                } footer: {
                    Text("先用离线和免费的来源，AI 只在你填了 Key 之后作为补充。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Link("源代码（MIT 许可）", destination: URL(string: "https://github.com/aquila0625/Lexpress")!)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
        .tint(.lxAccent)
    }

    private func test() {
        let config = AIClient.currentConfig
        testing = true
        testResult = nil
        Task {
            defer { testing = false }
            do {
                _ = try await AIClient.complete(system: "This is a connectivity check from an app's settings screen. Reply with the single word OK.",
                                                user: "ping", config: config)
                testResult = "连接正常"
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}
