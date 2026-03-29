import Foundation

public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
    func removeValue(forKey key: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? {
        storage[key]
    }

    public func set(_ value: Data, forKey key: String) {
        storage[key] = value
    }

    public func removeValue(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

public final class UserDefaultsKeyValueStore: KeyValueStore {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    public func set(_ value: Data, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}

public struct LLMSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var baseURL: String
    public var apiKey: String
    public var model: String

    public init(
        isEnabled: Bool,
        baseURL: String,
        apiKey: String,
        model: String
    ) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public static let disabled = Self(
        isEnabled: false,
        baseURL: "",
        apiKey: "",
        model: ""
    )

    public var isConfigured: Bool {
        isEnabled
        && normalizedBaseURL.isEmpty == false
        && normalizedAPIKey.isEmpty == false
        && normalizedModel.isEmpty == false
    }

    public var normalizedBaseURL: String {
        Self.trimmed(baseURL)
    }

    public var normalizedAPIKey: String {
        Self.trimmed(apiKey)
    }

    public var normalizedModel: String {
        Self.trimmed(model)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedLanguage: SupportedLanguage
    public var llm: LLMSettings

    public init(
        selectedLanguage: SupportedLanguage = .defaultLanguage,
        llm: LLMSettings = .disabled
    ) {
        self.selectedLanguage = selectedLanguage
        self.llm = llm
    }

    public static let defaults = Self(
        selectedLanguage: .defaultLanguage,
        llm: .disabled
    )
}

public final class AppSettingsStore {
    private enum StorageKey {
        static let snapshot = "voice-input.app-settings"
    }

    private let store: any KeyValueStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public convenience init() {
        self.init(store: UserDefaultsKeyValueStore())
    }

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public func load() -> AppSettings {
        guard
            let data = store.data(forKey: StorageKey.snapshot),
            let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return .defaults
        }

        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        store.set(data, forKey: StorageKey.snapshot)
    }
}
