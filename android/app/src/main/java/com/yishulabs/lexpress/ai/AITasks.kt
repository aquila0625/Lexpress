package com.yishulabs.lexpress.ai

import com.yishulabs.lexpress.core.AIUsage

/** Lexpress 里用到 AI 的几件事：优化机器翻译、帮用户写回复。 */
object AITasks {
    enum class ReplyKind(val title: String) { MESSAGE("短信 / 微信"), EMAIL("邮件") }

    enum class ReplyMode(val title: String) { POINTS("我说要点，AI 来写"), DRAFT("我写草稿，AI 优化") }

    class Reply(val text: String, val chinese: String, val usage: AIUsage?)

    // 优化译文

    suspend fun calibrate(source: String, machine: String, sourceIsChinese: Boolean, config: AIClient.Config): AIResponse {
        val system = """
            You review machine translations between English and Simplified Chinese for a dictionary and translation app. The user gives you a source text and a machine translation of it.

            Return an improved translation in the target language. Fix mistranslations, wrong word senses, unnatural phrasing and awkward word order, while keeping the meaning, tone and line breaks of the source. If the machine translation is already accurate and natural, return it unchanged.

            Output only the translation itself, with no explanation, quotation marks or labels: the app shows your output to the user directly as the translation.
        """.trimIndent()
        val user = """
            <source>
            $source
            </source>
            <machine_translation>
            $machine
            </machine_translation>
            Target language: ${if (sourceIsChinese) "English" else "Simplified Chinese"}
        """.trimIndent()
        return AIClient.complete(system, user, config)
    }

    // 写回复

    private const val SEPARATOR = "===ZH==="

    /** previous + change：在上一版回复的基础上按要求修改（更短、更正式……） */
    suspend fun reply(
        received: String, kind: ReplyKind, mode: ReplyMode, input: String,
        previous: String? = null, change: String? = null, config: AIClient.Config,
    ): Reply {
        val kindRule = when (kind) {
            ReplyKind.MESSAGE -> "The reply is a text message (SMS or WeChat): short, natural and conversational, with no subject line and no sign-off."
            ReplyKind.EMAIL -> "The reply is an email: begin with a line `Subject: ...`, then a greeting, the body and a sign-off. Use [Your name] where the sender's name goes."
        }
        val modeRule = when (mode) {
            ReplyMode.POINTS -> "The user describes what they want to say, often in Chinese. Write the reply from those points. Do not add commitments, facts or details the user did not mention."
            ReplyMode.DRAFT -> "The user wrote a draft of the reply themselves. Keep their meaning and level of detail; only fix grammar, word choice and tone."
        }
        val system = """
            You help the user of a translation app reply to a message they received. The user is a Chinese speaker.

            Write the reply in the same language as the received message, so the user can paste it straight back to the sender. $kindRule $modeRule

            After the reply, add a faithful Simplified Chinese translation of it so the user can check what they are about to send.

            Format your answer as: the reply, then a line containing exactly $SEPARATOR, then the Chinese translation. Write nothing else, because the app splits your answer on that line and shows both parts to the user.
        """.trimIndent()
        var user = """
            <received_message>
            $received
            </received_message>
            <user_input>
            $input
            </user_input>
        """.trimIndent()
        if (previous != null && change != null) {
            user += "\n" + """
                <previous_reply>
                $previous
                </previous_reply>
                <requested_change>
                $change
                </requested_change>
                Revise the previous reply according to the requested change.
            """.trimIndent()
        }
        val response = AIClient.complete(system, user, config)
        val parts = response.text.split(SEPARATOR)
        return Reply(parts[0].trim(), parts.getOrNull(1)?.trim() ?: "", response.usage)
    }
}
