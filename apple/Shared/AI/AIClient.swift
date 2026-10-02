import Foundation

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 用用户自己的 key 直接请求 AI 服务商，中间不经过任何 Lexpress 的服务器。
enum AIClient {
    struct Config {
        let provider: AIProvider
        let apiKey: String
        let model: String
        let baseURL: String
    }

    @MainActor
    static var currentConfig: Config {
        let s = AISettings.shared
        return Config(provider: s.provider, apiKey: s.apiKey.trimmed, model: s.model.trimmed, baseURL: s.baseURL.trimmed)
    }

    static func complete(system: String, user: String, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty else { throw AIError(message: "还没有填写 API Key。") }
        switch config.provider {
        case .claude: return try await claude(system: system, user: user, config: config)
        case .openai, .deepseek, .custom: return try await openAICompatible(system: system, user: user, config: config)
        }
    }

    // MARK: Claude（Anthropic Messages API）

    private static func claude(system: String, user: String, config: Config) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        // 新模型的安全分类器偶尔会误拒正常请求，让服务端自动换到推荐的后备模型重试
        if supportsDefaultFallback(config.model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await send(request)
        if json["stop_reason"] as? String == "refusal" {
            throw AIError(message: "AI 拒绝了这次请求，可以改一下内容再试。")
        }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.trimmed.isEmpty else { throw AIError(message: "AI 没有返回内容。") }
        return text.trimmed
    }

    private static func supportsDefaultFallback(_ model: String) -> Bool {
        model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5") || model == "claude-sonnet-5-5"
    }

    // MARK: OpenAI 兼容接口（ChatGPT、DeepSeek 和自定义服务商）

    private static func openAICompatible(system: String, user: String, config: Config) async throws -> String {
        var base = config.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"), url.scheme?.hasPrefix("http") == true else {
            throw AIError(message: "接口地址不正确。")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ] as [String: Any])

        let json = try await send(request)
        let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        guard let text = message?["content"] as? String, !text.trimmed.isEmpty else {
            throw AIError(message: "AI 没有返回内容。")
        }
        return text.trimmed
    }

    // MARK: 公共

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError(message: "连不上 AI 服务，请检查网络。")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String
            switch status {
            case 401, 403: throw AIError(message: "API Key 无效或没有权限。")
            case 429: throw AIError(message: "请求太频繁或额度用完了，稍后再试。")
            default: throw AIError(message: detail ?? "AI 服务出错（\(status)）。")
            }
        }
        return json
    }
}
