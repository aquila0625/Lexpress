import SwiftUI

/// 句子 / 段落的翻译结果。原文就是上面的输入框，这里只显示译文和操作。
struct SentenceView: View {
    let result: SentenceResult
    @ObservedObject var model: TranslatorModel
    /// 需要 AI 但还没配置时，打开设置
    let onNeedAI: () -> Void
    let onReply: () -> Void

    @ObservedObject private var ai = AISettings.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if result.calibrated {
                    Chip(text: result.machineTranslation == nil ? "AI 已优化 · 无需修改" : "AI 已优化",
                         systemName: "sparkles", ai: true)
                } else {
                    Chip(text: result.engine, systemName: "checkmark")
                }
                if model.isCalibrating {
                    ProgressView().controlSize(.small)
                    Text("AI 优化中…").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Text(result.translation)
                .font(.system(size: 20, weight: .medium))
                .lineSpacing(5)
                .textSelection(.enabled)

            if let machine = result.machineTranslation {
                (Text("优化前　").fontWeight(.semibold) + Text(machine))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.lxSurface, in: .rect(cornerRadius: 14))
                    .textSelection(.enabled)
            }

            if let usage = result.aiUsage {
                Text(usage.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lxAI)
            }

            if let error = model.aiError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.lxAI)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    basicActions
                    aiActions
                }
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
    }

    @ViewBuilder
    private var basicActions: some View {
        SpeakPill(speech: .text(result.translation, isChinese: !result.sourceIsChinese))
        GlassPillButton(title: copied ? "已复制" : "复制", systemName: copied ? "checkmark" : "doc.on.doc") {
            Clipboard.copy(result.translation)
            copied = true
        }
        // 把译文放到上面再反向翻译一次，用来检查意思有没有走样
        GlassPillButton(title: "对调", systemName: "arrow.up.arrow.down") {
            model.swapWithTranslation()
        }
    }

    @ViewBuilder
    private var aiActions: some View {
        if !result.calibrated, !model.isCalibrating {
            GlassPillButton(title: "AI 优化", systemName: "sparkles", tint: .lxAI) {
                ai.isConfigured ? model.calibrate() : onNeedAI()
            }
        }
        GlassPillButton(title: "写回复", systemName: "arrowshape.turn.up.left", tint: .lxAI) {
            ai.isConfigured ? onReply() : onNeedAI()
        }
    }
}
