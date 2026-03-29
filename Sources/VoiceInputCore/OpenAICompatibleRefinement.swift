import Foundation

public struct OpenAICompatibleChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OpenAICompatibleChatCompletionRequest: Codable, Equatable, Sendable {
    public var model: String
    public var messages: [OpenAICompatibleChatMessage]
    public var temperature: Double

    public init(
        model: String,
        messages: [OpenAICompatibleChatMessage],
        temperature: Double
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
    }
}

public struct OpenAICompatibleChatCompletionResponse: Decodable, Equatable, Sendable {
    public struct Choice: Decodable, Equatable, Sendable {
        public var message: OpenAICompatibleChatMessage?

        public init(message: OpenAICompatibleChatMessage?) {
            self.message = message
        }
    }

    public var choices: [Choice]

    public init(choices: [Choice]) {
        self.choices = choices
    }
}

public enum OpenAICompatibleRefinementError: LocalizedError, Equatable, Sendable {
    case incompleteConfiguration
    case emptyTranscript
    case invalidBaseURL(String)
    case missingAssistantContent

    public var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            "LLM 配置不完整"
        case .emptyTranscript:
            "转写文本为空"
        case let .invalidBaseURL(baseURL):
            "无效的 API Base URL：\(baseURL)"
        case .missingAssistantContent:
            "响应里没有可用的 assistant 内容"
        }
    }
}

public struct OpenAICompatibleRefinementRequestBuilder {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = encoder
    }

    public func buildRequest(config: LLMSettings, transcript: String) throws -> URLRequest {
        guard config.isConfigured else {
            throw OpenAICompatibleRefinementError.incompleteConfiguration
        }

        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTranscript.isEmpty == false else {
            throw OpenAICompatibleRefinementError.emptyTranscript
        }

        let requestBody = OpenAICompatibleChatCompletionRequest(
            model: config.normalizedModel,
            messages: [
                OpenAICompatibleChatMessage(
                    role: .system,
                    content: Self.systemPrompt
                ),
                OpenAICompatibleChatMessage(
                    role: .user,
                    content: normalizedTranscript
                ),
            ],
            temperature: 0
        )

        var request = URLRequest(url: try normalizedEndpoint(from: config.normalizedBaseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.normalizedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)
        return request
    }

    private func normalizedEndpoint(from baseURL: String) throws -> URL {
        guard
            var components = URLComponents(string: baseURL),
            components.scheme?.isEmpty == false,
            components.host?.isEmpty == false
        else {
            throw OpenAICompatibleRefinementError.invalidBaseURL(baseURL)
        }

        let trimmedPath = components.path
            .split(separator: "/")
            .map(String.init)
        let normalizedPathSegments: [String]

        if trimmedPath.suffix(2) == ["chat", "completions"] {
            normalizedPathSegments = trimmedPath
        } else {
            normalizedPathSegments = trimmedPath + ["chat", "completions"]
        }

        components.path = "/" + normalizedPathSegments.joined(separator: "/")
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw OpenAICompatibleRefinementError.invalidBaseURL(baseURL)
        }

        return url
    }

    private static let systemPrompt = """
    你是一个非常保守的语音识别纠错助手。只修复明显的语音识别错误，例如中文谐音错误、明显错误的英文技术术语或被误转成中文音译的术语。绝对不要改写、润色、扩写、删减、总结或重组内容。如果输入看起来已经正确，必须原样返回。只输出最终文本，不要解释。
    """
}

public struct OpenAICompatibleRefinementResponseParser {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func parse(data: Data) throws -> String {
        let response = try decoder.decode(OpenAICompatibleChatCompletionResponse.self, from: data)

        if let assistantContent = response.choices
            .compactMap({ normalizedContent(from: $0.message, preferredRole: .assistant) })
            .first {
            return assistantContent
        }

        if let fallbackContent = response.choices
            .compactMap({ normalizedContent(from: $0.message, preferredRole: nil) })
            .first {
            return fallbackContent
        }

        throw OpenAICompatibleRefinementError.missingAssistantContent
    }

    private func normalizedContent(
        from message: OpenAICompatibleChatMessage?,
        preferredRole: OpenAICompatibleChatMessage.Role?
    ) -> String? {
        guard let message else {
            return nil
        }

        if let preferredRole, message.role != preferredRole {
            return nil
        }

        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }
}
