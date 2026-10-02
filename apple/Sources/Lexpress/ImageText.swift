import AppKit
import Vision

/// 图片文字识别：用系统自带的 Vision，在本机完成，不上传图片。
enum ImageText {
    static func recognize(_ image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            // 不开自动检测时，纯英文图片会按中文模型识别，容易认错字母
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            return paragraphs(from: request.results ?? [])
        }.value
    }

    /// Vision 按“行”返回结果。同一段里折行的几行要拼回一段，否则会被当成几句话分别翻译。
    private static func paragraphs(from lines: [VNRecognizedTextObservation]) -> String {
        var output = ""
        var previous: VNRecognizedTextObservation?
        for line in lines {
            guard let text = line.topCandidates(1).first?.string, !text.isEmpty else { continue }
            if let previous {
                // 坐标原点在左下角。行距明显大于行高，或上一行明显短于这一行（标题、段末），就认为是新的一段
                let gap = previous.boundingBox.minY - line.boundingBox.maxY
                let lineHeight = min(previous.boundingBox.height, line.boundingBox.height)
                if gap > lineHeight * 0.5 || previous.boundingBox.width < line.boundingBox.width * 0.5 {
                    output += "\n"
                } else if !(output.last.map(isCJK) ?? false) || !(text.first.map(isCJK) ?? false) {
                    output += " "
                }
            }
            output += text
            previous = line
        }
        return output
    }

    /// 汉字或中文标点：这两类字符之间折行时不需要补空格
    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3000...0x303F).contains($0.value) || (0x3400...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value)
        }
    }
}
