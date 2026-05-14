import Foundation
import Security

struct AntigravityOAuthConfig: Codable, Equatable {
    var googleClientId: String
    var googleClientSecret: String
    var cloudCodeBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case googleClientId = "google_client_id"
        case googleClientSecret = "google_client_secret"
        case cloudCodeBaseURL = "cloud_code_base_url"
    }
}

protocol AntigravityOAuthConfigStore {
    func load() throws -> AntigravityOAuthConfig?
    func save(_ config: AntigravityOAuthConfig) throws
    func delete() throws
}

final class AntigravityOAuthKeychainStore: AntigravityOAuthConfigStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.relaybar.antigravity-oauth",
        account: String = "google-client"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> AntigravityOAuthConfig? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AntigravityOAuthConfigStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw AntigravityOAuthConfigStoreError.invalidPayload
        }
        do {
            return try JSONDecoder().decode(AntigravityOAuthConfig.self, from: data)
        } catch {
            throw AntigravityOAuthConfigStoreError.decoding(error.localizedDescription)
        }
    }

    func save(_ config: AntigravityOAuthConfig) throws {
        let normalized = try AntigravityOAuthConfigResolver.normalized(config)
        let data = try JSONEncoder().encode(normalized)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AntigravityOAuthConfigStoreError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AntigravityOAuthConfigStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AntigravityOAuthConfigStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum AntigravityOAuthConfigStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidPayload
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return L.antigravityOAuthKeychainError(message)
        case .invalidPayload:
            return L.antigravityOAuthConfigurationInvalid("Keychain item is not data")
        case .decoding(let message):
            return L.antigravityOAuthConfigurationInvalid(message)
        }
    }
}

final class AntigravityOAuthConfigResolver {
    static let shared = AntigravityOAuthConfigResolver()

    static let clientIdEnvironmentKey = "RELAYBAR_ANTIGRAVITY_GOOGLE_CLIENT_ID"
    static let googleSecretEnvironmentKey = "RELAYBAR_ANTIGRAVITY_GOOGLE_CLIENT_SECRET"
    static let cloudCodeBaseURLEnvironmentKey = "RELAYBAR_ANTIGRAVITY_CLOUD_CODE_BASE_URL"

    private let fileManager: FileManager
    private let environment: () -> [String: String]
    private let secureStore: AntigravityOAuthConfigStore?
    private let configURL: URL

    init(
        fileManager: FileManager = .default,
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        secureStore: AntigravityOAuthConfigStore? = AntigravityOAuthKeychainStore(),
        configURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.secureStore = secureStore
        self.configURL = configURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/relaybar", isDirectory: true)
            .appendingPathComponent("antigravity-oauth.json")
    }

    func load() throws -> AntigravityOAuthConfig {
        if let envConfig = configFromEnvironment() {
            return envConfig
        }

        if let storedConfig = try secureStore?.load() {
            return try Self.normalized(storedConfig)
        }

        guard fileManager.fileExists(atPath: configURL.path) else {
            throw AntigravityOAuthError.missingOAuthConfiguration
        }

        do {
            let data = try Data(contentsOf: configURL)
            try? SecureFileWriter.secureExistingSensitiveFile(at: configURL, fileManager: fileManager)
            let decoded = try JSONDecoder().decode(AntigravityOAuthConfig.self, from: data)
            return try Self.normalized(decoded)
        } catch let error as AntigravityOAuthError {
            throw error
        } catch {
            throw AntigravityOAuthError.invalidOAuthConfiguration(error.localizedDescription)
        }
    }

    private func configFromEnvironment() -> AntigravityOAuthConfig? {
        let env = environment()
        guard
            let clientId = trimmed(env[Self.clientIdEnvironmentKey]),
            let googleSecret = trimmed(env[Self.googleSecretEnvironmentKey])
        else {
            return nil
        }

        return AntigravityOAuthConfig(
            googleClientId: clientId,
            googleClientSecret: googleSecret,
            cloudCodeBaseURL: trimmed(env[Self.cloudCodeBaseURLEnvironmentKey])
        )
    }

    static func normalized(_ config: AntigravityOAuthConfig) throws -> AntigravityOAuthConfig {
        guard let clientId = trimmed(config.googleClientId),
              let googleSecret = trimmed(config.googleClientSecret) else {
            throw AntigravityOAuthError.missingOAuthConfiguration
        }

        return AntigravityOAuthConfig(
            googleClientId: clientId,
            googleClientSecret: googleSecret,
            cloudCodeBaseURL: trimmed(config.cloudCodeBaseURL)
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func trimmed(_ value: String?) -> String? {
        Self.trimmed(value)
    }
}

enum AntigravityOAuthError: LocalizedError {
    case invalidURL
    case stateMismatch
    case noRefreshToken
    case invalidResponse
    case missingOAuthConfiguration
    case invalidOAuthConfiguration(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Antigravity OAuth URL 无效"
        case .stateMismatch:
            return "Antigravity OAuth state 验证失败"
        case .noRefreshToken:
            return "未获取到 Antigravity refresh token，请撤销 Google 授权后重试"
        case .invalidResponse:
            return "Antigravity OAuth 响应无效"
        case .missingOAuthConfiguration:
            return L.antigravityOAuthConfigurationMissing
        case .invalidOAuthConfiguration(let message):
            return L.antigravityOAuthConfigurationInvalid(message)
        case .serverError(let message):
            return "Antigravity OAuth 失败: \(message)"
        }
    }
}
