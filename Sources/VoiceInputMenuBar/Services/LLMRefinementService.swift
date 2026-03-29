import Foundation
import VoiceInputCore

@MainActor
struct LLMRefinementService {
    private let session = URLSession.shared
    private let requestBuilder = OpenAICompatibleRefinementRequestBuilder()
    private let responseParser = OpenAICompatibleRefinementResponseParser()

    func refine(transcript: String, settings: LLMSettings) async throws -> String {
        let request = try requestBuilder.buildRequest(config: settings, transcript: transcript)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try responseParser.parse(data: data)
    }

    func test(settings: LLMSettings) async throws -> String {
        let probe = "把配森脚本转成杰森"
        return try await refine(transcript: probe, settings: settings)
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMRefinementError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMRefinementError.http(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

enum LLMRefinementError: LocalizedError {
    case invalidResponse
    case http(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务返回了无效响应"
        case let .http(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}
