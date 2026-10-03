import AppKit
import Translation

// 命令行自检：Q-Translator --lookup <词或句子>，不启动界面，方便验证接口是否还可用
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--lookup" {
    let query = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    Task {
        let chinese = query.containsChinese
        if let entry = try? await Youdao.lookup(query).entry {
            print("【词典】\(entry.word)  \(entry.phonetics.map { "\($0.label)/\($0.ipa)/" }.joined(separator: " "))\(entry.pinyin ?? "")")
            entry.definitions.forEach { print("  汇总: \($0.text) \($0.note ?? "")") }
            entry.senses.forEach { print("  义项: [\($0.pos ?? "")]\($0.isCommon ? "[常用]" : "") \($0.meaning) (例句 \($0.examples.count))") }
            print("  词形: \(entry.forms.joined(separator: " · "))")
            entry.examples.forEach { print("  例句: \($0.source.strippingTags)\n        \($0.translation)") }
            entry.phrases.forEach { print("  搭配: \($0.key) = \($0.value)") }
            entry.related.forEach { print("  同根: \($0.pos) \($0.word) \($0.meaning)") }
            entry.distinctions.forEach { print("  辨析: \($0.title) (\($0.usages.count) 个词)") }
            print("  柯林斯 \(entry.collins.count) 条；词源 \(entry.etymology == nil ? "无" : "有")")
        } else {
            print("【词典】无词条")
        }
        let zh = Locale.Language(identifier: "zh-Hans"), en = Locale.Language(identifier: "en")
        let status = await LanguageAvailability().status(from: chinese ? zh : en, to: chinese ? en : zh)
        print("【系统离线翻译模型】\(status)")
        do {
            print("【在线翻译】\(try await OnlineTranslator.translate(query, fromChinese: chinese))")
        } catch {
            print("【在线翻译】失败: \(error.localizedDescription)")
        }
        exit(0)
    }
    dispatchMain()
}

// 命令行自检：Q-Translator --ocr <图片路径>，打印识别出的文字
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--ocr" {
    Task {
        guard let image = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
            print("无法读取图片")
            exit(1)
        }
        print((try? await ImageText.recognize(image)) ?? "识别失败")
        exit(0)
    }
    dispatchMain()
}

// NSApplication 只弱引用 delegate，所以放在顶层持有
let delegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.delegate = delegate
    // 选了“只在菜单栏显示”时不出现在程序坞
    app.setActivationPolicy(UserDefaults.standard.bool(forKey: MenuBarKey.hideDockIcon) ? .accessory : .regular)
    app.run()
}
