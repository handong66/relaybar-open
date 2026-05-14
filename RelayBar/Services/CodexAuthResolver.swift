import Foundation

struct CodexAuthSnapshot {
    let sourceURL: URL
    let authMode: String
    let lastRefresh: Date?
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String

    var loginIdentity: String? {
        guard let idToken, !idToken.isEmpty else { return nil }
        let identity = TokenAccount.loginIdentity(userSubject: "", email: "", idToken: idToken)
        return identity.isEmpty ? nil : identity
    }
}

final class CodexAuthResolver {
    static let shared = CodexAuthResolver()

    let defaultAuthURL: URL
    let readCandidates: [URL]

    private let writeTargets: [URL]
    private let fileManager: FileManager
    private let session: URLSession
    private let dateFormatter = ISO8601DateFormatter()

    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let tokenURL = "https://auth.openai.com/oauth/token"

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        paths: CodexPaths = CodexPathResolver.resolve()
    ) {
        self.fileManager = fileManager
        self.session = session
        self.defaultAuthURL = paths.defaultAuthURL
        self.readCandidates = paths.authReadCandidates
        self.writeTargets = paths.authWriteTargets
    }

    func loadActiveAuth() -> Result<CodexAuthSnapshot?, CodexAuthResolverError> {
        var firstError: CodexAuthResolverError?

        for candidate in readCandidates where fileManager.fileExists(atPath: candidate.path) {
            do {
                let data = try Data(contentsOf: candidate)
                try? SecureFileWriter.secureExistingSensitiveFile(at: candidate, fileManager: fileManager)
                guard !data.isEmpty else { continue }
                let snapshot = try decodeSnapshot(from: data, sourceURL: candidate)
                return .success(snapshot)
            } catch let resolverError as CodexAuthResolverError {
                firstError = firstError ?? resolverError
            } catch {
                firstError = firstError ?? .readFailed(candidate, error)
            }
        }

        if let firstError {
            return .failure(firstError)
        }
        return .success(nil)
    }

    func writeActiveAuth(for account: TokenAccount) throws {
        let data = try encodedAuthData(for: account)
        for target in writeTargets {
            do {
                try SecureFileWriter.createPrivateDirectory(
                    at: target.deletingLastPathComponent(),
                    fileManager: fileManager
                )
                try backupIfNeeded(at: target)
                try SecureFileWriter.writeSensitiveData(data, to: target, fileManager: fileManager)
            } catch let resolverError as CodexAuthResolverError {
                throw resolverError
            } catch {
                throw CodexAuthResolverError.writeFailed(target, error)
            }
        }
    }

    func refreshTokens(for account: TokenAccount) async throws -> TokenAccount {
        guard !account.refreshToken.isEmpty else {
            throw CodexAuthResolverError.missingRefreshToken
        }
        guard let url = URL(string: tokenURL) else {
            throw CodexAuthResolverError.invalidTokenEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": account.refreshToken,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexAuthResolverError.refreshRequestFailed(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CodexAuthResolverError.invalidTokenResponse
        }

        guard http.statusCode == 200 else {
            throw CodexAuthResolverError.refreshRejected(http.statusCode, errorMessage(from: data))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthResolverError.invalidTokenResponse
        }

        if let error = json["error"] as? String {
            let description = json["error_description"] as? String
            throw CodexAuthResolverError.refreshRejected(http.statusCode, [error, description].compactMap { $0 }.joined(separator: ": "))
        }

        guard let accessToken = json["access_token"] as? String else {
            throw CodexAuthResolverError.invalidTokenResponse
        }

        let refreshedTokens = OAuthTokens(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? account.refreshToken,
            idToken: (json["id_token"] as? String) ?? account.idToken
        )
        return AccountBuilder.refreshed(existing: account, with: refreshedTokens)
    }

    private func decodeSnapshot(from data: Data, sourceURL: URL) throws -> CodexAuthSnapshot {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            let refreshToken = tokens["refresh_token"] as? String,
            let accountId = tokens["account_id"] as? String
        else {
            throw CodexAuthResolverError.invalidAuthFormat(sourceURL)
        }

        let lastRefresh: Date?
        if let rawDate = json["last_refresh"] as? String {
            lastRefresh = dateFormatter.date(from: rawDate)
        } else {
            lastRefresh = nil
        }

        return CodexAuthSnapshot(
            sourceURL: sourceURL,
            authMode: json["auth_mode"] as? String ?? "chatgpt",
            lastRefresh: lastRefresh,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: tokens["id_token"] as? String,
            accountId: accountId
        )
    }

    private func encodedAuthData(for account: TokenAccount) throws -> Data {
        let authDict: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "last_refresh": dateFormatter.string(from: Date()),
            "tokens": [
                "access_token": account.accessToken,
                "refresh_token": account.refreshToken,
                "id_token": account.idToken,
                "account_id": account.accountId,
            ]
        ]

        guard JSONSerialization.isValidJSONObject(authDict) else {
            throw CodexAuthResolverError.invalidAuthFormat(defaultAuthURL)
        }

        do {
            return try JSONSerialization.data(withJSONObject: authDict, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw CodexAuthResolverError.encodingFailed(error)
        }
    }

    private func backupIfNeeded(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let backupURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        do {
            try SecureFileWriter.copySensitiveItem(at: url, to: backupURL, fileManager: fileManager)
        } catch {
            throw CodexAuthResolverError.writeFailed(backupURL, error)
        }
    }

    private func formEncodedBody(_ values: [String: String]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let body = values
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }

    private func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let error = json["error"] as? String
        let description = json["error_description"] as? String
        return [error, description].compactMap { $0 }.joined(separator: ": ")
    }
}

enum CodexAuthResolverError: LocalizedError {
    case readFailed(URL, Error)
    case invalidAuthFormat(URL)
    case encodingFailed(Error)
    case writeFailed(URL, Error)
    case invalidTokenEndpoint
    case invalidTokenResponse
    case missingRefreshToken
    case refreshRequestFailed(Error)
    case refreshRejected(Int, String?)

    var errorDescription: String? {
        switch self {
        case .readFailed(let url, _):
            return "读取认证信息失败: \(url.path)"
        case .invalidAuthFormat(let url):
            return "认证文件格式无效: \(url.path)"
        case .encodingFailed:
            return "编码认证信息失败"
        case .writeFailed(let url, _):
            return "写入认证信息失败: \(url.path)"
        case .invalidTokenEndpoint:
            return "刷新 token 的地址无效"
        case .invalidTokenResponse:
            return "刷新 token 的响应无效"
        case .missingRefreshToken:
            return "缺少 refresh token，无法自动续期"
        case .refreshRequestFailed:
            return "请求刷新 token 失败"
        case .refreshRejected(let statusCode, let message):
            if let message, !message.isEmpty {
                return "刷新 token 被拒绝 (\(statusCode)): \(message)"
            }
            return "刷新 token 被拒绝 (\(statusCode))"
        }
    }
}
