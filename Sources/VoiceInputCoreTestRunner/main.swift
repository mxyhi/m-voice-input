import Foundation
import VoiceInputCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

func testSupportedLanguage() throws {
    try expect(SupportedLanguage.defaultLanguage == .simplifiedChinese, "默认语言应为简体中文")
    try expect(
        SupportedLanguage.menuOrderedCases == [.english, .simplifiedChinese, .traditionalChinese, .japanese, .korean],
        "语言菜单顺序不正确"
    )
    try expect(SupportedLanguage.japanese.localeIdentifier == "ja-JP", "日语 locale 不正确")
}

func testAppSettings() throws {
    let store = InMemoryKeyValueStore()
    let settingsStore = AppSettingsStore(store: store)
    let fallback = settingsStore.load()
    try expect(fallback.selectedLanguage == .simplifiedChinese, "默认设置应回退到简体中文")
    try expect(fallback.llm.isEnabled == false, "默认 LLM 应关闭")

    let snapshot = AppSettings(
        selectedLanguage: .korean,
        llm: LLMSettings(
            isEnabled: true,
            baseURL: "https://example.com/v1",
            apiKey: "sk-test",
            model: "gpt-4.1-mini"
        )
    )
    settingsStore.save(snapshot)
    try expect(settingsStore.load() == snapshot, "设置 round-trip 失败")
}

func testWaveformProcessor() throws {
    var processor = WaveformLevelProcessor(randomSource: .constant(0))
    let idle = processor.process(rms: 0)
    try expect(idle.count == 5, "波形 bar 数量必须为 5")
    try expect(idle.allSatisfy { $0 >= 0.18 }, "静音时波形也必须可见")

    let loud = processor.process(rms: 0.9)
    try expect(loud[2] > loud[0], "中间 bar 应高于左侧")
    try expect(loud[2] > loud[4], "中间 bar 应高于右侧")
}

func testRefinementProtocol() throws {
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

    try expect(
        request.url?.absoluteString == "https://example.com/v1/chat/completions",
        "chat completions endpoint 拼接错误"
    )

    guard let body = request.httpBody else {
        throw TestFailure(description: "请求体为空")
    }

    let envelope = try JSONDecoder().decode(OpenAICompatibleChatCompletionRequest.self, from: body)
    try expect(envelope.messages.count == 2, "message 数量错误")
    try expect(
        envelope.messages[0].content.contains("只修复明显的语音识别错误"),
        "system prompt 不够保守"
    )

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

    let refined = try OpenAICompatibleRefinementResponseParser().parse(data: data)
    try expect(refined == "把 Python 脚本转成 JSON", "response parser trim 失败")
}

do {
    try testSupportedLanguage()
    try testAppSettings()
    try testWaveformProcessor()
    try testRefinementProtocol()
    print("VoiceInputCoreTestRunner: all checks passed")
} catch {
    fputs("VoiceInputCoreTestRunner failed: \(error)\n", stderr)
    exit(1)
}
