import Foundation

final class AntigravityAccountImporter {
    static let shared = AntigravityAccountImporter()

    private let paths: AntigravityPaths
    private let oauthClient: AntigravityOAuthClient
    private let tokenRefresher: AntigravityTokenRefresher
    private let fileManager: FileManager

    init(
        paths: AntigravityPaths = AntigravityPathResolver.resolve(),
        oauthClient: AntigravityOAuthClient = .shared,
        tokenRefresher: AntigravityTokenRefresher = .shared,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.oauthClient = oauthClient
        self.tokenRefresher = tokenRefresher
        self.fileManager = fileManager
    }

    func importCurrentLogin() async throws -> AntigravityAccount {
        guard fileManager.fileExists(atPath: paths.stateDatabaseURL.path) else {
            throw AntigravitySwitchError.databaseMissing(paths.stateDatabaseURL.path)
        }

        let state = try Self.extractCurrentLoginState(from: paths.stateDatabaseURL)
        try state.validateLocalStateConsistency()
        let profile = try? AntigravityDeviceProfileIO.read(from: paths.storageJSONURL)

        if state.canImportFromLocalState(),
           let accessToken = state.accessToken,
           let email = state.email {
            return Self.makeAccount(
                from: state,
                accessToken: accessToken,
                email: email,
                displayName: email,
                profile: profile
            )
        }

        if state.hasFreshAccessToken(),
           let accessToken = state.accessToken {
            let userInfo: AntigravityGoogleUserInfo?
            if state.email == nil {
                userInfo = try? await oauthClient.fetchUserInfo(accessToken: accessToken)
            } else {
                userInfo = nil
            }
            guard let email = state.email ?? userInfo?.email else {
                throw AntigravityImportError.missingUserEmail
            }
            var account = Self.makeAccount(
                from: state,
                accessToken: accessToken,
                email: email,
                displayName: userInfo?.displayName ?? email,
                profile: profile
            )
            if account.token.projectId == nil {
                account.token.projectId = try? await oauthClient.fetchProjectId(accessToken: accessToken)
            }
            return account
        }

        var token = AntigravityTokenData(
            accessToken: state.accessToken ?? "",
            refreshToken: state.refreshToken,
            expiresIn: 0,
            email: state.email,
            projectId: state.projectId,
            oauthClientKey: AntigravityOAuthClient.defaultClientKey,
            isGcpTos: state.isGcpTos,
            idToken: state.idToken,
            expiryTimestamp: state.expiryTimestamp,
            tokenType: state.tokenType
        )
        token = try await tokenRefresher.refresh(token: token)
        let userInfo = try await oauthClient.fetchUserInfo(accessToken: token.accessToken)
        if token.projectId == nil {
            token.projectId = try? await oauthClient.fetchProjectId(accessToken: token.accessToken)
        }
        token.email = userInfo.email

        return AntigravityAccount(
            email: userInfo.email,
            name: userInfo.displayName,
            token: token,
            deviceProfile: profile ?? AntigravityDeviceProfile.generate(),
            isActive: true
        )
    }

    static func extractCurrentLoginState(from dbURL: URL) throws -> ImportedAntigravityOAuthState {
        let db = try AntigravitySQLiteDatabase(url: dbURL)
        let localStateSnapshot = try captureLocalStateSnapshot(from: db)

        if let oauthEntry = try db.queryString(
            "SELECT value FROM ItemTable WHERE key = ?",
            bindings: ["antigravityUnifiedStateSync.oauthToken"]
        ) {
            let (sentinel, payload) = try AntigravityProtobuf.decodeUnifiedStateEntry(oauthEntry)
            guard sentinel == "oauthTokenInfoSentinelKey" else {
                throw AntigravityImportError.unexpectedSentinel(sentinel)
            }

            let refreshData = try AntigravityProtobuf
                .findField(payload, fieldNumber: 3)
                .required("Refresh token not found in Antigravity OAuth payload")
            guard let refreshToken = String(data: refreshData, encoding: .utf8), !refreshToken.isEmpty else {
                throw AntigravityImportError.missingRefreshToken
            }

            let accessToken = try stringField(payload, fieldNumber: 1)
            let tokenType = try stringField(payload, fieldNumber: 2) ?? "Bearer"
            let idToken = try stringField(payload, fieldNumber: 5)
            let expiryTimestamp = try expiryTimestamp(from: payload)
            let isGcpTos = try AntigravityProtobuf.findVarintField(payload, fieldNumber: 6).map { $0 != 0 } ?? true
            return ImportedAntigravityOAuthState(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiryTimestamp: expiryTimestamp,
                tokenType: tokenType,
                email: try extractUserEmail(from: db),
                isGcpTos: isGcpTos,
                projectId: try extractProjectId(from: db),
                idToken: idToken,
                localStateSnapshot: localStateSnapshot
            )
        }

        if let legacyEntry = try db.queryString(
            "SELECT value FROM ItemTable WHERE key = ?",
            bindings: ["jetskiStateSync.agentManagerInitState"]
        ) {
            guard let blob = Data(base64Encoded: legacyEntry) else {
                throw AntigravityImportError.invalidLegacyState
            }
            let oauthData = try AntigravityProtobuf
                .findField(blob, fieldNumber: 6)
                .required("OAuth payload not found in legacy Antigravity state")
            let refreshData = try AntigravityProtobuf
                .findField(oauthData, fieldNumber: 3)
                .required("Refresh token not found in legacy Antigravity OAuth payload")
            guard let refreshToken = String(data: refreshData, encoding: .utf8), !refreshToken.isEmpty else {
                throw AntigravityImportError.missingRefreshToken
            }

            return ImportedAntigravityOAuthState(
                accessToken: try stringField(oauthData, fieldNumber: 1),
                refreshToken: refreshToken,
                expiryTimestamp: try expiryTimestamp(from: oauthData),
                tokenType: try stringField(oauthData, fieldNumber: 2) ?? "Bearer",
                email: try extractUserEmail(from: db),
                isGcpTos: true,
                projectId: try extractProjectId(from: db),
                idToken: try stringField(oauthData, fieldNumber: 5),
                localStateSnapshot: localStateSnapshot
            )
        }

        throw AntigravityImportError.loginStateNotFound
    }

    private static func captureLocalStateSnapshot(from db: AntigravitySQLiteDatabase) throws -> AntigravityLocalStateSnapshot {
        let placeholders = AntigravityLocalStateSnapshot.capturedStateKeys.map { _ in "?" }.joined(separator: ",")
        let rows = try db.queryStringRows(
            "SELECT key, value FROM ItemTable WHERE key IN (\(placeholders))",
            bindings: AntigravityLocalStateSnapshot.capturedStateKeys
        )

        var stateItems: [String: String] = [:]
        for row in rows {
            guard row.count >= 2,
                  let key = row[0],
                  let value = row[1],
                  AntigravityLocalStateSnapshot.capturedStateKeys.contains(key) else {
                continue
            }
            stateItems[key] = value
        }

        let missingKeys = AntigravityLocalStateSnapshot.capturedStateKeys
            .filter { stateItems[$0] == nil }
        return AntigravityLocalStateSnapshot(
            stateItems: stateItems,
            missingStateKeys: missingKeys
        )
    }

    private static func extractUserEmail(from db: AntigravitySQLiteDatabase) throws -> String? {
        guard let statusEntry = try db.queryString(
            "SELECT value FROM ItemTable WHERE key = ?",
            bindings: ["antigravityUnifiedStateSync.userStatus"]
        ) else {
            return nil
        }

        let (_, payload) = try AntigravityProtobuf.decodeUnifiedStateEntry(statusEntry)
        return try stringField(payload, fieldNumber: 3) ?? stringField(payload, fieldNumber: 7)
    }

    private static func extractProjectId(from db: AntigravitySQLiteDatabase) throws -> String? {
        guard let projectEntry = try db.queryString(
            "SELECT value FROM ItemTable WHERE key = ?",
            bindings: ["antigravityUnifiedStateSync.enterprisePreferences"]
        ) else {
            return nil
        }

        let (sentinel, payload) = try AntigravityProtobuf.decodeUnifiedStateEntry(projectEntry)
        guard sentinel == "enterpriseGcpProjectId" else {
            return nil
        }

        guard let projectData = try AntigravityProtobuf.findField(payload, fieldNumber: 3),
              let projectId = String(data: projectData, encoding: .utf8),
              !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return projectId
    }

    private static func stringField(_ payload: Data, fieldNumber: UInt32) throws -> String? {
        guard let data = try AntigravityProtobuf.findField(payload, fieldNumber: fieldNumber),
              let value = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func expiryTimestamp(from payload: Data) throws -> Date {
        guard let timestampPayload = try AntigravityProtobuf.findField(payload, fieldNumber: 4),
              let seconds = try AntigravityProtobuf.findVarintField(timestampPayload, fieldNumber: 1) else {
            return Date(timeIntervalSince1970: 0)
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func makeAccount(
        from state: ImportedAntigravityOAuthState,
        accessToken: String,
        email: String,
        displayName: String,
        profile: AntigravityDeviceProfile?
    ) -> AntigravityAccount {
        let token = AntigravityTokenData(
            accessToken: accessToken,
            refreshToken: state.refreshToken,
            expiresIn: Int(max(0, state.expiryTimestamp.timeIntervalSinceNow)),
            email: email,
            projectId: state.projectId,
            oauthClientKey: AntigravityOAuthClient.defaultClientKey,
            isGcpTos: state.isGcpTos,
            idToken: state.idToken,
            expiryTimestamp: state.expiryTimestamp,
            tokenType: state.tokenType
        )
        return AntigravityAccount(
            email: email,
            name: displayName,
            token: token,
            deviceProfile: profile ?? AntigravityDeviceProfile.generate(),
            localStateSnapshot: state.localStateSnapshot,
            isActive: true
        )
    }
}

struct ImportedAntigravityOAuthState {
    var accessToken: String?
    var refreshToken: String
    var expiryTimestamp: Date
    var tokenType: String
    var email: String?
    var isGcpTos: Bool
    var projectId: String?
    var idToken: String? = nil
    var localStateSnapshot: AntigravityLocalStateSnapshot? = nil

    func hasFreshAccessToken(now: Date = Date()) -> Bool {
        guard let accessToken, !accessToken.isEmpty else { return false }
        return expiryTimestamp.timeIntervalSince(now) > 120
    }

    func canImportWithoutRefresh(now: Date = Date()) -> Bool {
        guard let email, !email.isEmpty else { return false }
        return hasFreshAccessToken(now: now)
    }

    func canImportFromLocalState() -> Bool {
        guard let accessToken, !accessToken.isEmpty else { return false }
        guard !refreshToken.isEmpty else { return false }
        guard let email, !email.isEmpty else { return false }
        return true
    }

    func validateLocalStateConsistency() throws {
        guard localStateSnapshot?.hasConsistentAuthenticationEmail(email) != false else {
            throw AntigravityImportError.inconsistentLocalState(email ?? "")
        }
    }
}

enum AntigravityImportError: LocalizedError {
    case loginStateNotFound
    case missingRefreshToken
    case missingUserEmail
    case unexpectedSentinel(String)
    case invalidLegacyState
    case inconsistentLocalState(String)

    var errorDescription: String? {
        switch self {
        case .loginStateNotFound:
            return "未在 Antigravity state.vscdb 中找到登录状态，请先在 Antigravity 登录一次"
        case .missingRefreshToken:
            return "Antigravity 登录状态中没有 refresh token"
        case .missingUserEmail:
            return "Antigravity 登录状态中没有账号邮箱，请重新打开 Antigravity 后再导入"
        case .unexpectedSentinel(let sentinel):
            return "Antigravity 登录状态格式不匹配: \(sentinel)"
        case .invalidLegacyState:
            return "Antigravity 旧版登录状态无法解析"
        case .inconsistentLocalState(let email):
            if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "当前 Antigravity 本地登录状态不一致。请先在官方 Antigravity 重新登录目标账号，再回 RelayBar 重新授权。"
            }
            return "当前 Antigravity 本地登录状态混合了其他账号，不是完整的 \(email) 登录快照。请先在官方 Antigravity 重新登录该账号，再回 RelayBar 重新授权。"
        }
    }
}
