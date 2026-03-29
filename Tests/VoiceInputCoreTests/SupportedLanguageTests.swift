import Testing
@testable import VoiceInputCore

struct SupportedLanguageTests {
    @Test
    func defaultLanguage_isSimplifiedChinese() {
        #expect(SupportedLanguage.defaultLanguage == .simplifiedChinese)
    }

    @Test
    func menuOrdering_matchesProductRequirements() {
        #expect(
            SupportedLanguage.menuOrderedCases == [.english, .simplifiedChinese, .traditionalChinese, .japanese, .korean]
        )
    }

    @Test
    func localeIdentifiers_areStable() {
        #expect(SupportedLanguage.simplifiedChinese.localeIdentifier == "zh-CN")
        #expect(SupportedLanguage.traditionalChinese.localeIdentifier == "zh-TW")
        #expect(SupportedLanguage.japanese.localeIdentifier == "ja-JP")
        #expect(SupportedLanguage.korean.localeIdentifier == "ko-KR")
    }
}
