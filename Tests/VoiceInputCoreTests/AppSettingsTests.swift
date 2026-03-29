import Testing
@testable import VoiceInputCore

struct AppSettingsTests {
    @Test
    func defaultsFallback_usesSimplifiedChineseAndDisabledLLM() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettingsStore(store: store)

        let snapshot = settings.load()

        #expect(snapshot.selectedLanguage == .simplifiedChinese)
        #expect(snapshot.llm.isEnabled == false)
        #expect(snapshot.llm.baseURL == "")
        #expect(snapshot.llm.apiKey == "")
        #expect(snapshot.llm.model == "")
    }

    @Test
    func saveRoundTrip_persistsAllFields() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettingsStore(store: store)
        let expected = AppSettings(
            selectedLanguage: .japanese,
            llm: LLMSettings(
                isEnabled: true,
                baseURL: "https://example.com/v1",
                apiKey: "sk-test",
                model: "gpt-4.1-mini"
            )
        )

        settings.save(expected)

        #expect(settings.load() == expected)
    }

    @Test
    func llmIsConfigured_requiresEnableFlagAndNonEmptyFields() {
        #expect(
            LLMSettings(
                isEnabled: false,
                baseURL: "https://example.com/v1",
                apiKey: "k",
                model: "m"
            ).isConfigured == false
        )
        #expect(
            LLMSettings(
                isEnabled: true,
                baseURL: "",
                apiKey: "k",
                model: "m"
            ).isConfigured == false
        )
        #expect(
            LLMSettings(
                isEnabled: true,
                baseURL: "https://example.com/v1/",
                apiKey: "k",
                model: "m"
            ).isConfigured == true
        )
    }
}
