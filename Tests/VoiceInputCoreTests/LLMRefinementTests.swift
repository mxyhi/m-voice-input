import Foundation
import Testing
@testable import VoiceInputCore

struct LLMRefinementTests {
    @Test
    func requestBuildsConservativeSystemPromptAndNormalizedEndpoint() throws {
        let config = LLMSettings(
            isEnabled: true,
            baseURL: "https://example.com/v1/",
            apiKey: "sk-test",
            model: "gpt-4.1-mini"
        )

        let request = try OpenAICompatibleRefinementRequestBuilder().buildRequest(
            config: config,
            transcript: "把配森脚本转成杰森"
        )

        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(OpenAICompatibleChatCompletionRequest.self, from: body)

        #expect(envelope.model == "gpt-4.1-mini")
        #expect(envelope.messages.count == 2)
        #expect(envelope.messages[0].content.contains("只修复明显的语音识别错误"))
        #expect(envelope.messages[1].content == "把配森脚本转成杰森")
    }

    @Test
    func responseParser_prefersTrimmedAssistantContent() throws {
        let data = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "  把 Python 脚本转成 JSON  "
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try OpenAICompatibleRefinementResponseParser().parse(data: data)

        #expect(result == "把 Python 脚本转成 JSON")
    }

    @Test
    func responseParser_rejectsMissingContent() {
        let data = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "   "
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let didThrow: Bool
        do {
            _ = try OpenAICompatibleRefinementResponseParser().parse(data: data)
            didThrow = false
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
