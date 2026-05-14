import Foundation

struct AntigravityAccount: Codable, Identifiable {
    var id: String
    var email: String
    var name: String?
    var token: AntigravityTokenData
    var deviceProfile: AntigravityDeviceProfile?
    var localStateSnapshot: AntigravityLocalStateSnapshot?
    var quota: AntigravityQuotaData?
    var isActive: Bool
    var tokenExpired: Bool
    var disabled: Bool
    var disabledReason: String?
    var validationBlocked: Bool
    var validationBlockedReason: String?
    var createdAt: Date
    var lastUsed: Date
    var lastChecked: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case token
        case deviceProfile = "device_profile"
        case localStateSnapshot = "local_state_snapshot"
        case quota
        case isActive = "is_active"
        case tokenExpired = "token_expired"
        case disabled
        case disabledReason = "disabled_reason"
        case validationBlocked = "validation_blocked"
        case validationBlockedReason = "validation_blocked_reason"
        case createdAt = "created_at"
        case lastUsed = "last_used"
        case lastChecked = "last_checked"
    }

    init(
        id: String = UUID().uuidString,
        email: String,
        name: String? = nil,
        token: AntigravityTokenData,
        deviceProfile: AntigravityDeviceProfile? = nil,
        localStateSnapshot: AntigravityLocalStateSnapshot? = nil,
        quota: AntigravityQuotaData? = nil,
        isActive: Bool = false,
        tokenExpired: Bool = false,
        disabled: Bool = false,
        disabledReason: String? = nil,
        validationBlocked: Bool = false,
        validationBlockedReason: String? = nil,
        createdAt: Date = Date(),
        lastUsed: Date = Date(),
        lastChecked: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.token = token
        self.deviceProfile = deviceProfile
        self.localStateSnapshot = localStateSnapshot
        self.quota = quota
        self.isActive = isActive
        self.tokenExpired = tokenExpired
        self.disabled = disabled
        self.disabledReason = disabledReason
        self.validationBlocked = validationBlocked
        self.validationBlockedReason = validationBlockedReason
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.lastChecked = lastChecked
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return email
    }

    var tierLabel: String {
        guard let rawTier = quota?.subscriptionTier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTier.isEmpty else {
            return "AG"
        }

        let lowered = rawTier.lowercased()
        if lowered.contains("ultra") { return "ULTRA" }
        if lowered.contains("pro") { return "PRO" }
        if lowered.contains("plus") { return "PLUS" }
        if lowered.contains("free") { return "FREE" }
        return rawTier.uppercased()
    }

    var accessTokenNeedsRefresh: Bool {
        if tokenExpired { return true }
        return token.expiryDate.timeIntervalSinceNow <= 900
    }

    var hasRefreshToken: Bool {
        !token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasLocalSwitchSnapshot: Bool {
        localStateSnapshot?.hasSwitchableAuthState == true
    }

    var canSwitchLocally: Bool {
        (hasLocalSwitchSnapshot || hasRefreshToken) && !disabled && !validationBlocked
    }

    var isForbidden: Bool {
        quota?.isForbidden == true
    }

    var isAvailable: Bool {
        canSwitchLocally && !isForbidden
    }

    var usageMetricSections: [UsageMetricSection] {
        guard let quota else { return [] }

        var sections: [UsageMetricSection] = []
        if quota.isForbidden {
            sections.append(
                UsageMetricSection(
                    id: "antigravity-status",
                    title: L.usageStatusLabel,
                    lines: [
                        .badge(
                            UsageBadgeMetricLine(
                                id: "antigravity-forbidden",
                                label: L.usageStatusLabel,
                                value: L.antigravityForbidden,
                                tone: .critical
                            )
                        )
                    ]
                )
            )
        }

        let modelLines = quota.prominentDisplayModels(limit: 10).flatMap { model -> [UsageMetricLine] in
            let tone = AntigravityQuotaData.tone(for: model.remainingPercent)
            var lines: [UsageMetricLine] = [
                .progress(
                    UsageProgressMetricLine(
                        id: "ag-\(model.id)-progress",
                        label: model.displayTitle,
                        remainingPercent: Double(model.remainingPercent),
                        valueText: "\(model.remainingPercent)%",
                        tone: tone
                    )
                )
            ]

            if let resetDescription = model.resetDescription, !resetDescription.isEmpty {
                lines.append(
                    .text(
                        UsageTextMetricLine(
                            id: "ag-\(model.id)-reset",
                            leading: resetDescription,
                            trailing: nil,
                            tone: .secondary
                        )
                    )
                )
            }

            return lines
        }

        if !modelLines.isEmpty {
            sections.append(
                UsageMetricSection(
                    id: "antigravity-model-quota",
                    title: L.antigravityQuotaTitle,
                    lines: modelLines
                )
            )
        }

        return sections
    }

    func heroUsageMetricSections(limit: Int = 3) -> [UsageMetricSection] {
        guard let quota else { return [] }

        let prominentModels = quota.prominentDisplayModels(limit: limit)
        guard !prominentModels.isEmpty else { return usageMetricSections }

        let lines = prominentModels.flatMap { model -> [UsageMetricLine] in
            var modelLines: [UsageMetricLine] = [
                .progress(
                    UsageProgressMetricLine(
                        id: "ag-hero-\(model.id)-progress",
                        label: model.displayTitle,
                        remainingPercent: Double(model.remainingPercent),
                        valueText: "\(model.remainingPercent)%",
                        tone: AntigravityQuotaData.tone(for: model.remainingPercent)
                    )
                )
            ]

            if let resetDescription = model.resetDescription, !resetDescription.isEmpty {
                modelLines.append(
                    .text(
                        UsageTextMetricLine(
                            id: "ag-hero-\(model.id)-reset",
                            leading: resetDescription,
                            trailing: nil,
                            tone: .secondary
                        )
                    )
                )
            }

            return modelLines
        }

        return [
            UsageMetricSection(
                id: "antigravity-model-quota-hero",
                title: L.antigravityQuotaTitle,
                lines: lines
            )
        ]
    }

    func secondaryUsageMetricSections(limit: Int = 1) -> [UsageMetricSection] {
        guard let quota else { return [] }
        let models = quota.prominentDisplayModels(limit: limit)
        guard !models.isEmpty else { return [] }

        let lines = models.map { model in
            UsageMetricLine.progress(
                UsageProgressMetricLine(
                    id: "ag-secondary-\(model.id)-progress",
                    label: model.displayTitle,
                    remainingPercent: Double(model.remainingPercent),
                    valueText: "\(model.remainingPercent)%",
                    tone: AntigravityQuotaData.tone(for: model.remainingPercent)
                )
            )
        }

        return [
            UsageMetricSection(
                id: "antigravity-model-quota-secondary",
                title: L.antigravityQuotaTitle,
                lines: lines
            )
        ]
    }

    func overflowDisplayModelCount(limit: Int = 3) -> Int {
        guard let quota else { return 0 }
        return quota.overflowDisplayModels(limit: limit).count
    }
}

struct AntigravityLocalStateSnapshot: Codable, Hashable {
    static let capturedStateKeys = [
        "antigravityUnifiedStateSync.oauthToken",
        "antigravityUnifiedStateSync.userStatus",
        "antigravityUnifiedStateSync.enterprisePreferences",
        "antigravityAuthStatus",
        "jetskiStateSync.agentManagerInitState",
        "google.antigravity",
        "antigravityOnboarding"
    ]

    var stateItems: [String: String]
    var missingStateKeys: [String]
    var capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case stateItems = "state_items"
        case missingStateKeys = "missing_state_keys"
        case capturedAt = "captured_at"
    }

    init(
        stateItems: [String: String],
        missingStateKeys: [String],
        capturedAt: Date = Date()
    ) {
        self.stateItems = stateItems
        self.missingStateKeys = missingStateKeys
        self.capturedAt = capturedAt
    }

    var hasSwitchableAuthState: Bool {
        stateItems["antigravityUnifiedStateSync.oauthToken"] != nil
            || stateItems["jetskiStateSync.agentManagerInitState"] != nil
    }

    func hasConsistentAuthenticationEmail(_ email: String?) -> Bool {
        guard let expected = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              expected.contains("@") else {
            return true
        }

        let authRows = [
            stateItems["antigravityAuthStatus"],
            stateItems["jetskiStateSync.agentManagerInitState"],
            stateItems["google.antigravity"]
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
        let emails = Self.emails(in: authRows)
            .filter { $0 != "git@github.com" }
        return emails.isEmpty || emails.contains(expected)
    }

    private static func emails(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(
            regex.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]).lowercased() }
            }
        )
    }
}

struct AntigravityTokenData: Codable, Hashable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var expiryTimestamp: Date
    var tokenType: String
    var email: String?
    var projectId: String?
    var oauthClientKey: String?
    var isGcpTos: Bool
    var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiryTimestamp = "expiry_timestamp"
        case tokenType = "token_type"
        case email
        case projectId = "project_id"
        case oauthClientKey = "oauth_client_key"
        case isGcpTos = "is_gcp_tos"
        case idToken = "id_token"
    }

    init(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        email: String? = nil,
        projectId: String? = nil,
        oauthClientKey: String? = nil,
        isGcpTos: Bool = true,
        idToken: String? = nil,
        expiryTimestamp: Date? = nil,
        tokenType: String = "Bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.expiryTimestamp = expiryTimestamp ?? Date().addingTimeInterval(TimeInterval(expiresIn))
        self.tokenType = tokenType.isEmpty ? "Bearer" : tokenType
        self.email = email
        self.projectId = projectId
        self.oauthClientKey = oauthClientKey
        self.isGcpTos = isGcpTos
        self.idToken = idToken
    }

    var expiryDate: Date { expiryTimestamp }
}

struct AntigravityDeviceProfile: Codable, Hashable {
    var machineId: String
    var macMachineId: String
    var devDeviceId: String
    var sqmId: String

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case macMachineId = "mac_machine_id"
        case devDeviceId = "dev_device_id"
        case sqmId = "sqm_id"
    }

    static func generate() -> AntigravityDeviceProfile {
        AntigravityDeviceProfile(
            machineId: "auth0|user_\(randomLowercaseString(length: 32))",
            macMachineId: UUID().uuidString.lowercased(),
            devDeviceId: UUID().uuidString.lowercased(),
            sqmId: "{\(UUID().uuidString.uppercased())}"
        )
    }

    private static func randomLowercaseString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

struct AntigravityQuotaData: Codable, Hashable {
    var models: [AntigravityModelQuota]
    var lastUpdated: Date
    var isForbidden: Bool
    var forbiddenReason: String?
    var subscriptionTier: String?

    enum CodingKeys: String, CodingKey {
        case models
        case lastUpdated = "last_updated"
        case isForbidden = "is_forbidden"
        case forbiddenReason = "forbidden_reason"
        case subscriptionTier = "subscription_tier"
    }

    init(
        models: [AntigravityModelQuota] = [],
        lastUpdated: Date = Date(),
        isForbidden: Bool = false,
        forbiddenReason: String? = nil,
        subscriptionTier: String? = nil
    ) {
        self.models = models
        self.lastUpdated = lastUpdated
        self.isForbidden = isForbidden
        self.forbiddenReason = forbiddenReason
        self.subscriptionTier = subscriptionTier
    }

    var displayModels: [AntigravityModelQuota] {
        Array(rankedDisplayModels.prefix(10))
    }

    func prominentDisplayModels(limit: Int) -> [AntigravityModelQuota] {
        Array(rankedDisplayModels.prefix(max(limit, 0)))
    }

    func overflowDisplayModels(limit: Int) -> [AntigravityModelQuota] {
        Array(rankedDisplayModels.dropFirst(max(limit, 0)))
    }

    private var rankedDisplayModels: [AntigravityModelQuota] {
        let filtered = deduplicatedDisplayModels(from: models)
            .filter { model in
                let text = searchableText(for: model)
                return text.contains("gemini")
                    || text.contains("claude")
                    || text.contains("anthropic")
                    || text.contains("gpt")
                    || text.contains("image")
                    || text.contains("imagen")
            }
            .sorted { lhs, rhs in
                if lhs.remainingPercent != rhs.remainingPercent {
                    return lhs.remainingPercent < rhs.remainingPercent
                }

                let leftRank = familyRank(for: lhs)
                let rightRank = familyRank(for: rhs)
                if leftRank != rightRank { return leftRank < rightRank }

                if (lhs.recommended ?? false) != (rhs.recommended ?? false) {
                    return lhs.recommended == true
                }
                return lhs.displayTitle < rhs.displayTitle
            }
        return filtered
    }

    var allDisplayedModelsEmpty: Bool {
        let display = displayModels
        return !display.isEmpty && display.allSatisfy { $0.remainingPercent <= 0 }
    }

    static func tone(for remainingPercent: Int) -> UsageMetricTone {
        if remainingPercent <= 10 { return .critical }
        if remainingPercent <= 30 { return .warning }
        return .positive
    }

    private func deduplicatedDisplayModels(from models: [AntigravityModelQuota]) -> [AntigravityModelQuota] {
        var modelsByDisplayName: [String: AntigravityModelQuota] = [:]

        for model in models {
            let key = normalizedDisplayKey(for: model)
            guard !key.isEmpty else { continue }

            if let existing = modelsByDisplayName[key] {
                modelsByDisplayName[key] = preferredDuplicate(existing, model)
            } else {
                modelsByDisplayName[key] = model
            }
        }

        return Array(modelsByDisplayName.values)
    }

    private func preferredDuplicate(
        _ lhs: AntigravityModelQuota,
        _ rhs: AntigravityModelQuota
    ) -> AntigravityModelQuota {
        if lhs.remainingPercent != rhs.remainingPercent {
            return lhs.remainingPercent < rhs.remainingPercent ? lhs : rhs
        }

        if (lhs.recommended ?? false) != (rhs.recommended ?? false) {
            return lhs.recommended == true ? lhs : rhs
        }

        if lhs.resetTime.isEmpty != rhs.resetTime.isEmpty {
            return lhs.resetTime.isEmpty ? rhs : lhs
        }

        if !lhs.resetTime.isEmpty, !rhs.resetTime.isEmpty, lhs.resetTime != rhs.resetTime {
            return lhs.resetTime < rhs.resetTime ? lhs : rhs
        }

        return lhs.name.count <= rhs.name.count ? lhs : rhs
    }

    private func normalizedDisplayKey(for model: AntigravityModelQuota) -> String {
        model.displayTitle
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchableText(for model: AntigravityModelQuota) -> String {
        "\(model.name) \(model.displayTitle)"
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func familyRank(for model: AntigravityModelQuota) -> Int {
        let text = searchableText(for: model)
        if text.contains("gemini 3") { return 0 }
        if text.contains("claude") || text.contains("anthropic") { return 1 }
        if text.contains("gpt") { return 2 }
        if text.contains("gemini 2.5") { return 3 }
        if text.contains("image") || text.contains("imagen") { return 4 }
        if text.contains("gemini") { return 5 }
        return 6
    }
}

struct AntigravityModelQuota: Codable, Hashable, Identifiable {
    var name: String
    var remainingPercent: Int
    var resetTime: String
    var displayName: String?
    var supportsImages: Bool?
    var supportsThinking: Bool?
    var thinkingBudget: Int?
    var recommended: Bool?
    var maxTokens: Int?
    var maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case remainingPercent = "percentage"
        case resetTime = "reset_time"
        case displayName = "display_name"
        case supportsImages = "supports_images"
        case supportsThinking = "supports_thinking"
        case thinkingBudget = "thinking_budget"
        case recommended
        case maxTokens = "max_tokens"
        case maxOutputTokens = "max_output_tokens"
    }

    var id: String { name }

    var displayTitle: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }

        return name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { token in
                let lowered = token.lowercased()
                if lowered == "gpt" { return "GPT" }
                if lowered == "gemini" { return "Gemini" }
                if lowered == "claude" { return "Claude" }
                return lowered.capitalized
            }
            .joined(separator: " ")
    }

    var resetDescription: String? {
        guard let date = Self.parseResetDate(resetTime) else { return nil }
        return UsageWindowSnapshot.resetDescription(for: date)
    }

    private static func parseResetDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

struct AntigravityAccountPool: Codable {
    var version: Int
    var currentAccountId: String?
    var accounts: [AntigravityAccount]

    enum CodingKeys: String, CodingKey {
        case version
        case currentAccountId = "current_account_id"
        case accounts
    }

    init(version: Int = 1, currentAccountId: String? = nil, accounts: [AntigravityAccount] = []) {
        self.version = version
        self.currentAccountId = currentAccountId
        self.accounts = accounts
    }
}
