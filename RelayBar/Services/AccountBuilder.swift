import Foundation

/// 从 OAuth tokens 解析账号信息，构建 TokenAccount
struct AccountBuilder {
    static func build(from tokens: OAuthTokens) -> TokenAccount {
        let claims = decodeJWT(tokens.accessToken)
        let authClaims = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]

        let accountId = authClaims["chatgpt_account_id"] as? String ?? ""
        let planType = authClaims["chatgpt_plan_type"] as? String ?? "free"

        // 从 id_token 取 email
        let idClaims = decodeJWT(tokens.idToken)
        let email = idClaims["email"] as? String ?? ""
        let userSubject = idClaims["sub"] as? String ?? ""

        return TokenAccount(
            email: email,
            accountId: accountId,
            userSubject: userSubject,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            idToken: tokens.idToken,
            planType: planType
        )
    }

    static func refreshed(existing account: TokenAccount, with tokens: OAuthTokens) -> TokenAccount {
        var updated = build(from: tokens)
        updated.primaryUsedPercent = account.primaryUsedPercent
        updated.secondaryUsedPercent = account.secondaryUsedPercent
        updated.primaryResetAt = account.primaryResetAt
        updated.secondaryResetAt = account.secondaryResetAt
        updated.lastChecked = account.lastChecked
        updated.isActive = account.isActive
        updated.isSuspended = false
        updated.tokenExpired = false
        updated.organizationName = account.organizationName
        updated.usageSnapshot = account.usageSnapshot
        return updated
    }

    /// 解码 JWT payload（不验签）
    static func decodeJWT(_ token: String) -> [String: Any] {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return [:] }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }
}
