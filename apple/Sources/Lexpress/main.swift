import AppKit
import Translation

// 命令行自检：Lexpress --lookup <词或句子>，不启动界面，方便验证接口是否还可用
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--lookup" {
    let query = CommandLine.arguments.dropFirst(2).joined(separator: " ")
    Task {
        let chinese = query.containsChinese
        if let entry = try? await Youdao.lookup(query).entry {
            print("【词典】\(entry.word)  \(entry.phonetics.map { "\($0.label)/\($0.ipa)/" }.joined(separator: " "))\(entry.pinyin ?? "")")
            entry.definitions.forEach { print("  释义: \($0.text) \($0.note ?? "")") }
            print("  词形: \(entry.forms.joined(separator: " · "))")
            entry.collins.forEach { print("  柯林斯: [\($0.pos ?? "")] \($0.explanation.strippingTags) (例句 \($0.examples.count))") }
            entry.examples.forEach { print("  例句: \($0.source.strippingTags)\n        \($0.translation)") }
            entry.phrases.forEach { print("  词组: \($0.key) = \($0.value)") }
            entry.related.forEach { print("  同根: \($0.pos) \($0.word) \($0.meaning)") }
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

// 命令行自检：Lexpress --ocr <图片路径>，打印识别出的文字
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
    app.setActivationPolicy(.regular)
    app.run()
}
