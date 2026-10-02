import SwiftUI

/// 句子 / 段落的翻译结果，带 AI 校准和“写回复”的入口。
struct SentenceView: View {
    let result: SentenceResult
    @ObservedObject var model: TranslatorModel
    let wide: Bool
    /// 需要 AI 但还没配置时，打开设置
    let onNeedAI: () -> Void
    let onReply: () -> Void

    @ObservedObject private var ai = AISettings.shared
    @State private var copied = false

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: 20) {
                sourceCard.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) { translation }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                sourceCard
                translation
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: result.sourceIsChinese ? "原文 · 中文" : "原文 · 英文")
                SpeakButton { Speaker.shared.speak(result.source, isChinese: result.sourceIsChinese) }
                    .padding(.vertical, -10)
            }
            Text(result.source)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lxSurface, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var translation: some View {
        HStack(spacing: 8) {
            if result.calibrated {
                Chip(text: result.machineTranslation == nil ? "AI 已校准 · 无需修改" : "AI 已校准",
                     systemName: "sparkles", ai: true)
            } else {
                Chip(text: result.engine, systemName: "checkmark")
            }
            if model.isCalibrating {
                ProgressView().controlSize(.small)
                Text("AI 校准中…").font(.footnote).foregroundStyle(.secondary)
            }
        }

        Text(result.translation)
            .font(.system(size: 20, weight: .medium))
            .lineSpacing(5)
            .textSelection(.enabled)

        if let machine = result.machineTranslation {
            (Text("校准前　").fontWeight(.semibold) + Text(machine))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.lxSurface, in: .rect(cornerRadius: 14))
                .textSelection(.enabled)
        }

        if let error = model.aiError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Color.lxAI)
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actions }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { basicActions }
                HStack(spacing: 8) { aiActions }
            }
        }

        if model.canDownloadOffline {
            Button("下载系统离线翻译模型（更快、不限量、无需联网）") { model.downloadOfflineModel() }
                .font(.callout)
                .frame(minHeight: 44)
        }

        if !result.suggestions.isEmpty {
            Block("你是不是要找") {
                VStack(spacing: 0) {
                    ForEach(result.suggestions) { s in
                        PhraseRow(key: s.word, value: s.meaning, serif: true) { model.lookup(s.word) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        basicActions
        aiActions
    }

    @ViewBuilder
    private var basicActions: some View {
        GlassPillButton(title: "朗读", systemName: "speaker.wave.2") {
            Speaker.shared.speak(result.translation, isChinese: !result.sourceIsChinese)
        }
        GlassPillButton(title: copied ? "已复制" : "复制", systemName: copied ? "checkmark" : "doc.on.doc") {
            Clipboard.copy(result.translation)
            copied = true
        }
    }

    @ViewBuilder
    private var aiActions: some View {
        if !result.calibrated, !model.isCalibrating {
            GlassPillButton(title: "AI 校准", systemName: "sparkles", tint: .lxAI) {
                ai.isConfigured ? model.calibrate() : onNeedAI()
            }
        }
        GlassPillButton(title: "写回复", systemName: "arrowshape.turn.up.left", tint: .lxAI) {
            ai.isConfigured ? onReply() : onNeedAI()
        }
    }
}
