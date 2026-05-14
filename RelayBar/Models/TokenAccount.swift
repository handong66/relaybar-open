import Foundation

struct TokenAccount: Codable, Identifiable {
    var id: String { storageKey }
    var email: String
    var accountId: String
    var userSubject: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var planType: String
    var primaryUsedPercent: Double   // 5h 窗口已使用%
    var secondaryUsedPercent: Double // 周窗口已使用%
    var primaryResetAt: Date?        // 5h 窗口重置绝对时间
    var secondaryResetAt: Date?      // 周窗口重置绝对时间
    var lastChecked: Date?
    var isActive: Bool
    var isSuspended: Bool       // 403 = 账号被封禁/停用
    var tokenExpired: Bool       // 401 = token 过期，需重新授权
    var organizationName: String?
    var usageSnapshot: UsageSnapshot?
    var localUsageSnapshot: LocalUsageSnapshot?

    enum CodingKeys: String, CodingKey {
        case email
        case accountId = "account_id"
        case userSubject = "user_subject"
        case organizationName = "organization_name"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case planType = "plan_type"
        case primaryUsedPercent = "primary_used_percent"
        case secondaryUsedPercent = "secondary_used_percent"
        case primaryResetAt = "primary_reset_at"
        case secondaryResetAt = "secondary_reset_at"
        case lastChecked = "last_checked"
        case isActive = "is_active"
        case isSuspended = "is_suspended"
        case tokenExpired = "token_expired"
        case usageSnapshot = "usage_snapshot"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        accountId = try c.decode(String.self, forKey: .accountId)
        userSubject = try c.decodeIfPresent(String.self, forKey: .userSubject) ?? ""
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        idToken = try c.decode(String.self, forKey: .idToken)
        planType = try c.decodeIfPresent(String.self, forKey: .planType) ?? "free"
        primaryUsedPercent = try c.decodeIfPresent(Double.self, forKey: .primaryUsedPercent) ?? 0
        secondaryUsedPercent = try c.decodeIfPresent(Double.self, forKey: .secondaryUsedPercent) ?? 0
        primaryResetAt = try c.decodeIfPresent(Date.self, forKey: .primaryResetAt)
        secondaryResetAt = try c.decodeIfPresent(Date.self, forKey: .secondaryResetAt)
        lastChecked = try c.decodeIfPresent(Date.self, forKey: .lastChecked)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isSuspended = try c.decodeIfPresent(Bool.self, forKey: .isSuspended) ?? false
        tokenExpired = try c.decodeIfPresent(Bool.self, forKey: .tokenExpired) ?? false
        organizationName = try c.decodeIfPresent(String.self, forKey: .organizationName)
        usageSnapshot = try c.decodeIfPresent(UsageSnapshot.self, forKey: .usageSnapshot)
        localUsageSnapshot = nil
    }

    init(email: String = "", accountId: String = "", userSubject: String = "", accessToken: String = "",
         refreshToken: String = "", idToken: String = "",
         planType: String = "free", primaryUsedPercent: Double = 0,
         secondaryUsedPercent: Double = 0,
         primaryResetAt: Date? = nil, secondaryResetAt: Date? = nil,
         lastChecked: Date? = nil, isActive: Bool = false, isSuspended: Bool = false, tokenExpired: Bool = false,
         organizationName: String? = nil, usageSnapshot: UsageSnapshot? = nil, localUsageSnapshot: LocalUsageSnapshot? = nil) {
        self.email = email
        self.accountId = accountId
        self.userSubject = userSubject
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.primaryResetAt = primaryResetAt
        self.secondaryResetAt = secondaryResetAt
        self.lastChecked = lastChecked
        self.isActive = isActive
        self.isSuspended = isSuspended
        self.tokenExpired = tokenExpired
        self.organizationName = organizationName
        self.usageSnapshot = usageSnapshot
        self.localUsageSnapshot = localUsageSnapshot
    }

    // MARK: - Computed

    var isBanned: Bool { isSuspended }
    var primaryExhausted: Bool { primaryUsedPercent >= 100 }
    var secondaryExhausted: Bool { secondaryUsedPercent >= 100 }
    var quotaExhausted: Bool { primaryExhausted || secondaryExhausted }
    var primaryRemainingPercent: Double { remainingPercent(from: primaryUsedPercent) }
    var secondaryRemainingPercent: Double { remainingPercent(from: secondaryUsedPercent) }
    var usageMetricSections: [UsageMetricSection] {
        UsageMetricSectionBuilder.buildSections(
            snapshot: usageSnapshot,
            fallbackPrimaryUsedPercent: primaryUsedPercent,
            fallbackSecondaryUsedPercent: secondaryUsedPercent,
            fallbackPrimaryResetAt: primaryResetAt,
            fallbackSecondaryResetAt: secondaryResetAt,
            localUsageSnapshot: localUsageSnapshot
        )
    }
    var localUsageMetricSections: [UsageMetricSection] {
        usageMetricSections.filter { $0.id == UsageMetricSectionBuilder.localUsageSectionID }
    }
    var secondaryUsageMetricSections: [UsageMetricSection] {
        usageMetricSections.filter { $0.id != UsageMetricSectionBuilder.localUsageSectionID }.prefix(1).map { $0 }
    }
    var accessTokenExpiresAt: Date? { Self.jwtExpirationDate(token: accessToken) }
    var accessTokenNeedsRefresh: Bool {
        if tokenExpired { return true }
        guard let accessTokenExpiresAt else { return false }
        return accessTokenExpiresAt.timeIntervalSinceNow <= 60
    }
    var loginIdentity: String {
        Self.loginIdentity(userSubject: userSubject, email: email, idToken: idToken)
    }
    var storageKey: String {
        Self.storageKey(accountId: accountId, userSubject: userSubject, email: email, idToken: idToken)
    }

    var usageStatus: UsageStatus {
        if isBanned { return .banned }
        if quotaExhausted { return .exceeded }
        if primaryUsedPercent >= 80 || secondaryUsedPercent >= 80 { return .warning }
        return .ok
    }

    var primaryResetDescription: String {
        UsageWindowSnapshot.resetDescription(for: primaryResetAt) ?? ""
    }

    var secondaryResetDescription: String {
        UsageWindowSnapshot.resetDescription(for: secondaryResetAt) ?? ""
    }

    private func remainingPercent(from usedPercent: Double) -> Double {
        min(max(100 - usedPercent, 0), 100)
    }

    static func loginIdentity(userSubject: String, email: String, idToken: String) -> String {
        if !userSubject.isEmpty { return userSubject }
        let claims = AccountBuilder.decodeJWT(idToken)
        if let sub = claims["sub"] as? String, !sub.isEmpty { return sub }
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func storageKey(accountId: String, userSubject: String, email: String, idToken: String) -> String {
        "\(accountId)::\(loginIdentity(userSubject: userSubject, email: email, idToken: idToken))"
    }

    func matches(accountId: String, loginIdentity: String?) -> Bool {
        guard self.accountId == accountId else { return false }
        guard let loginIdentity, !loginIdentity.isEmpty else { return true }
        return self.loginIdentity == loginIdentity
    }

    private static func jwtExpirationDate(token: String) -> Date? {
        let claims = AccountBuilder.decodeJWT(token)
        if let exp = claims["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = claims["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: exp.doubleValue)
        }
        return nil
    }
}

enum UsageStatus {
    case ok, warning, exceeded, banned

    var color: String {
        switch self {
        case .ok: return "green"
        case .warning: return "yellow"
        case .exceeded: return "orange"
        case .banned: return "red"
        }
    }

    var label: String {
        switch self {
        case .ok: return "正常"
        case .warning: return "即将用尽"
        case .exceeded: return "额度耗尽"
        case .banned: return "已停用"
        }
    }
}

struct TokenPool: Codable {
    var accounts: [TokenAccount]

    init(accounts: [TokenAccount] = []) {
        self.accounts = accounts
    }
}
