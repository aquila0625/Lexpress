import Foundation

/// Q-Translator 里用到 AI 的几件事：校准机器翻译、帮用户写回复。
enum AITasks {
    enum ReplyKind: String, CaseIterable, Identifiable {
        case message, email
        var id: String { rawValue }
        var title: String { self == .message ? "短信 / 微信" : "邮件" }
    }

    enum ReplyMode: String, CaseIterable, Identifiable {
        case points, draft
        var id: String { rawValue }
        var title: String { self == .points ? "我说要点，AI 来写" : "我写草稿，AI 优化" }
    }

    struct Reply {
        let text: String
        let chinese: String
        let usage: AIUsage?
    }

    // MARK: 校准译文

    static func calibrate(source: String, machine: String, sourceIsChinese: Bool, config: AIClient.Config) async throws -> AIResponse {
        let system = """
        You review machine translations between English and Simplified Chinese for a dictionary and translation app. \
        The user gives you a source text and a machine translation of it.

        Return an improved translation in the target language. Fix mistranslations, wrong word senses, unnatural \
        phrasing and awkward word order, while keeping the meaning, tone and line breaks of the source. \
        If the machine translation is already accurate and natural, return it unchanged.

        Output only the translation itself, with no explanation, quotation marks or labels: the app shows your \
        output to the user directly as the translation.
        """
        let user = """
        <source>
        \(source)
        </source>
        <machine_translation>
        \(machine)
        </machine_translation>
        Target language: \(sourceIsChinese ? "English" : "Simplified Chinese")
        """
        return try await AIClient.complete(system: system, user: user, config: config)
    }

    // MARK: 图片里的文字

    /// 把图片里识别出的几段文字一起翻译，可以带用户的要求（例如“只翻译菜名”）。返回和输入一一对应的译文，跳过的段是空字符串
    static func translateImageBlocks(_ blocks: [String], instruction: String?, toChinese: Bool,
                                     config: AIClient.Config) async throws -> (texts: [String], usage: AIUsage?) {
        let system = """
        You translate text that was recognized (OCR) from a photo in a translation app. The text comes as numbered \
        blocks; each block is one paragraph or label at its own place in the image, and the app draws your translation \
        over the original text at that place.

        Translate every block into \(toChinese ? "Simplified Chinese" : "English"). Keep translations about as short as \
        the original so they fit in the same space. Fix obvious OCR mistakes. If the user gives an instruction, follow it; \
        when the instruction says to leave some content out, use an empty string for those blocks.

        Answer with only a JSON array of strings, one per block in the same order, and nothing else: the app parses it.
        """
        var user = blocks.enumerated().map { "<block index=\"\($0.offset + 1)\">\n\($0.element)\n</block>" }.joined(separator: "\n")
        if let instruction, !instruction.trimmed.isEmpty {
            user += "\n<instruction>\n\(instruction.trimmed)\n</instruction>"
        }
        let response = try await AIClient.complete(system: system, user: user, config: config)
        var texts: [String] = []
        if let start = response.text.firstIndex(of: "["), let end = response.text.lastIndex(of: "]"),
           let data = String(response.text[start...end]).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            texts = decoded
        } else {
            throw AIError(message: "AI 返回的格式不对，可以重试。")
        }
        // 数量对不上时按位置补齐或截断
        texts = Array((texts + Array(repeating: "", count: max(0, blocks.count - texts.count))).prefix(blocks.count))
        return (texts, response.usage)
    }

    // MARK: 写回复

    private static let separator = "===ZH==="

    /// previous + change：在上一版回复的基础上按要求修改（更短、更正式……）
    static func reply(to received: String, kind: ReplyKind, mode: ReplyMode, input: String,
                      previous: String? = nil, change: String? = nil, config: AIClient.Config) async throws -> Reply {
        let kindRule = switch kind {
        case .message:
            "The reply is a text message (SMS or WeChat): short, natural and conversational, with no subject line and no sign-off."
        case .email:
            "The reply is an email: begin with a line `Subject: ...`, then a greeting, the body and a sign-off. Use [Your name] where the sender's name goes."
        }
        let modeRule = switch mode {
        case .points:
            "The user describes what they want to say, often in Chinese. Write the reply from those points. Do not add commitments, facts or details the user did not mention."
        case .draft:
            "The user wrote a draft of the reply themselves. Keep their meaning and level of detail; only fix grammar, word choice and tone."
        }
        let system = """
        You help the user of a translation app reply to a message they received. The user is a Chinese speaker.

        Write the reply in the same language as the received message, so the user can paste it straight back to \
        the sender. \(kindRule) \(modeRule)

        After the reply, add a faithful Simplified Chinese translation of it so the user can check what they are \
        about to send.

        Format your answer as: the reply, then a line containing exactly \(separator), then the Chinese translation. \
        Write nothing else, because the app splits your answer on that line and shows both parts to the user.
        """
        var user = """
        <received_message>
        \(received)
        </received_message>
        <user_input>
        \(input)
        </user_input>
        """
        if let previous, let change {
            user += """

            <previous_reply>
            \(previous)
            </previous_reply>
            <requested_change>
            \(change)
            </requested_change>
            Revise the previous reply according to the requested change.
            """
        }
        let response = try await AIClient.complete(system: system, user: user, config: config)
        let parts = response.text.components(separatedBy: separator)
        return Reply(text: parts[0].trimmed, chinese: parts.count > 1 ? parts[1].trimmed : "", usage: response.usage)
    }
}
