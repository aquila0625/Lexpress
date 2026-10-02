import SwiftUI

/// 圆形玻璃图标按钮（顶栏的历史、设置，以及词头旁的星标）
struct GlassIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// 胶囊形玻璃按钮（朗读、复制、写回复）
struct GlassPillButton: View {
    let title: String
    let systemName: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// 翻译方向：根据输入自动识别
struct DirectionPill: View {
    let sourceIsChinese: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(sourceIsChinese ? "中" : "英")
            Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(sourceIsChinese ? "英" : "中")
            Text("自动").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sourceIsChinese ? "中文翻译成英文，自动识别" : "英文翻译成中文，自动识别")
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// 带标题的一组内容
struct Block<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: Content

    init(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, trailing: trailing)
            content
        }
    }
}

/// 小标签：翻译来源、“AI 已校准”等
struct Chip: View {
    let text: String
    let systemName: String
    var ai = false

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ai ? Color.lxAI : Color.lxAccent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(ai ? Color.lxAISoft : Color.lxAccentSoft, in: .capsule)
    }
}

struct SpeakButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.footnote)
                .foregroundStyle(Color.lxAccent)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("朗读")
    }
}

struct ExampleRow: View {
    let example: ExamplePair

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            SpeakButton { Speaker.shared.english(example.english) }
                .padding(.top, -8)
            VStack(alignment: .leading, spacing: 2) {
                Text(rich(example.source)).font(.callout)
                if !example.translation.isEmpty {
                    Text(example.translation).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
        }
        .padding(.leading, -10)
    }
}

/// 一行“左边词、右边释义”，左边可点
struct PhraseRow: View {
    let key: String
    let value: String
    var serif = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: action) {
                Text(key)
                    .font(serif ? .system(.body, design: .serif).weight(.medium) : .callout.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.lxAccent)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 把接口返回的 <b>…</b> 高亮转成富文本，其余标签去掉。
func rich(_ html: String) -> AttributedString {
    var output = AttributedString()
    var rest = Substring(html)
    var bold = false

    func piece(_ text: Substring) -> AttributedString {
        var part = AttributedString(String(text).strippingTags)
        if bold {
            part.inlinePresentationIntent = .stronglyEmphasized
            part.foregroundColor = .lxAccent
        }
        return part
    }

    while let range = rest.range(of: bold ? "</b>" : "<b>") {
        output += piece(rest[..<range.lowerBound])
        rest = rest[range.upperBound...]
        bold.toggle()
    }
    output += piece(rest)
    return output
}
