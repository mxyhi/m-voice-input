public enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese
    case korean

    public static let defaultLanguage: Self = .simplifiedChinese

    public static let menuOrderedCases: [Self] = [
        .english,
        .simplifiedChinese,
        .traditionalChinese,
        .japanese,
        .korean,
    ]

    public var localeIdentifier: String {
        switch self {
        case .english:
            "en-US"
        case .simplifiedChinese:
            "zh-CN"
        case .traditionalChinese:
            "zh-TW"
        case .japanese:
            "ja-JP"
        case .korean:
            "ko-KR"
        }
    }

    public var displayName: String {
        switch self {
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁体中文"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        }
    }
}
