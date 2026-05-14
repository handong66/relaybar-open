import Foundation

enum CredentialTransferProvider: String, CaseIterable, Identifiable {
    case codex
    case antigravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex:
            return L.providerCodex
        case .antigravity:
            return L.providerAntigravity
        }
    }
}

enum CredentialImportConflictAction: String, CaseIterable, Identifiable {
    case overwrite
    case keepLocal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite:
            return L.credentialsConflictOverwrite
        case .keepLocal:
            return L.credentialsConflictKeepLocal
        }
    }
}

struct CredentialImportApplySummary {
    var addedCount: Int = 0
    var overwrittenCount: Int = 0
    var skippedCount: Int = 0
}

struct CredentialTransferSelectableItem: Identifiable {
    enum Payload {
        case codex(TokenAccount)
        case antigravity(AntigravityAccount)
    }

    let provider: CredentialTransferProvider
    let stableKey: String
    let title: String
    let detail: String
    let badgeText: String?
    let isSourceActive: Bool
    let hasConflict: Bool
    let payload: Payload

    var id: String {
        "\(provider.rawValue)::\(stableKey)"
    }

    var codexAccount: TokenAccount? {
        guard case .codex(let account) = payload else { return nil }
        return account
    }

    var antigravityAccount: AntigravityAccount? {
        guard case .antigravity(let account) = payload else { return nil }
        return account
    }
}

struct CredentialTransferSelectionResult {
    let codexAccounts: [TokenAccount]
    let activeCodexStorageKey: String?
    let antigravityPool: AntigravityAccountPool
    let codexConflictActions: [String: CredentialImportConflictAction]
    let antigravityConflictActions: [String: CredentialImportConflictAction]

    var selectedCount: Int {
        codexAccounts.count + antigravityPool.accounts.count
    }
}

struct CredentialTransferBundle: Codable {
    static let bundleType = AppIdentity.credentialBundleType
    static let currentVersion = 1

    var type: String
    var version: Int
    var exportedAt: Date
    var codexAccounts: [TokenAccount]
    var activeCodexStorageKey: String?
    var antigravityPool: AntigravityAccountPool

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case exportedAt = "exported_at"
        case codexAccounts = "codex_accounts"
        case activeCodexStorageKey = "active_codex_storage_key"
        case antigravityPool = "antigravity_pool"
    }

    init(
        type: String = CredentialTransferBundle.bundleType,
        version: Int = CredentialTransferBundle.currentVersion,
        exportedAt: Date = Date(),
        codexAccounts: [TokenAccount],
        activeCodexStorageKey: String?,
        antigravityPool: AntigravityAccountPool
    ) {
        self.type = type
        self.version = version
        self.exportedAt = exportedAt
        self.codexAccounts = codexAccounts
        self.activeCodexStorageKey = activeCodexStorageKey
        self.antigravityPool = antigravityPool
    }
}

final class CredentialTransferService {
    static let shared = CredentialTransferService()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func exportItems(
        codexAccounts: [TokenAccount],
        activeCodexStorageKey: String?,
        antigravityPool: AntigravityAccountPool
    ) -> [CredentialTransferSelectableItem] {
        let codexItems = codexAccounts.map { account in
            CredentialTransferSelectableItem(
                provider: .codex,
                stableKey: account.storageKey,
                title: account.email,
                detail: codexDetail(for: account),
                badgeText: account.planType.uppercased(),
                isSourceActive: activeCodexStorageKey == account.storageKey || account.isActive,
                hasConflict: false,
                payload: .codex(account)
            )
        }

        let antigravityItems = antigravityPool.accounts.map { account in
            CredentialTransferSelectableItem(
                provider: .antigravity,
                stableKey: account.id,
                title: account.email,
                detail: antigravityDetail(for: account),
                badgeText: account.tierLabel,
                isSourceActive: antigravityPool.currentAccountId == account.id || account.isActive,
                hasConflict: false,
                payload: .antigravity(account)
            )
        }

        return codexItems + antigravityItems
    }

    func importItems(
        from bundle: CredentialTransferBundle,
        existingCodexAccounts: [TokenAccount],
        existingAntigravityAccounts: [AntigravityAccount]
    ) -> [CredentialTransferSelectableItem] {
        let codexItems = bundle.codexAccounts.map { account in
            CredentialTransferSelectableItem(
                provider: .codex,
                stableKey: account.storageKey,
                title: account.email,
                detail: codexDetail(for: account),
                badgeText: account.planType.uppercased(),
                isSourceActive: bundle.activeCodexStorageKey == account.storageKey || account.isActive,
                hasConflict: hasCodexConflict(account, in: existingCodexAccounts),
                payload: .codex(account)
            )
        }

        let antigravityItems = bundle.antigravityPool.accounts.map { account in
            CredentialTransferSelectableItem(
                provider: .antigravity,
                stableKey: account.id,
                title: account.email,
                detail: antigravityDetail(for: account),
                badgeText: account.tierLabel,
                isSourceActive: bundle.antigravityPool.currentAccountId == account.id || account.isActive,
                hasConflict: hasAntigravityConflict(account, in: existingAntigravityAccounts),
                payload: .antigravity(account)
            )
        }

        return codexItems + antigravityItems
    }

    func makeSelectionResult(
        from items: [CredentialTransferSelectableItem],
        selectedItemIDs: Set<String>,
        conflictActions: [String: CredentialImportConflictAction]
    ) -> CredentialTransferSelectionResult {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }

        let selectedCodexAccounts = selectedItems.compactMap(\.codexAccount)
        let selectedAntigravityAccounts = selectedItems.compactMap(\.antigravityAccount)

        let selectedActiveCodexStorageKey = selectedItems.first {
            $0.provider == .codex && $0.isSourceActive
        }?.codexAccount?.storageKey

        let selectedCurrentAntigravityAccountId = selectedItems.first {
            $0.provider == .antigravity && $0.isSourceActive
        }?.antigravityAccount?.id

        var codexConflictActions: [String: CredentialImportConflictAction] = [:]
        var antigravityConflictActions: [String: CredentialImportConflictAction] = [:]

        for item in selectedItems where item.hasConflict {
            let action = conflictActions[item.id] ?? .overwrite
            switch item.payload {
            case .codex(let account):
                codexConflictActions[account.storageKey] = action
            case .antigravity(let account):
                antigravityConflictActions[account.id] = action
            }
        }

        return CredentialTransferSelectionResult(
            codexAccounts: selectedCodexAccounts,
            activeCodexStorageKey: selectedActiveCodexStorageKey,
            antigravityPool: AntigravityAccountPool(
                currentAccountId: selectedCurrentAntigravityAccountId,
                accounts: selectedAntigravityAccounts
            ),
            codexConflictActions: codexConflictActions,
            antigravityConflictActions: antigravityConflictActions
        )
    }

    func exportBundleData(from selectionResult: CredentialTransferSelectionResult) throws -> Data {
        guard selectionResult.selectedCount > 0 else {
            throw CredentialTransferError.emptySelection
        }

        return try encodeBundle(
            CredentialTransferBundle(
                codexAccounts: selectionResult.codexAccounts,
                activeCodexStorageKey: selectionResult.activeCodexStorageKey,
                antigravityPool: selectionResult.antigravityPool
            )
        )
    }

    func exportBundleData(
        codexAccounts: [TokenAccount],
        activeCodexStorageKey: String?,
        antigravityPool: AntigravityAccountPool
    ) throws -> Data {
        try encodeBundle(
            CredentialTransferBundle(
                codexAccounts: codexAccounts,
                activeCodexStorageKey: activeCodexStorageKey,
                antigravityPool: antigravityPool
            )
        )
    }

    func importBundleData(_ data: Data) throws -> CredentialTransferBundle {
        let bundle: CredentialTransferBundle
        do {
            bundle = try decoder.decode(CredentialTransferBundle.self, from: data)
        } catch {
            throw CredentialTransferError.invalidFormat
        }

        guard Self.isSupportedBundleType(bundle.type) else {
            throw CredentialTransferError.invalidFormat
        }

        guard bundle.version == CredentialTransferBundle.currentVersion else {
            throw CredentialTransferError.unsupportedVersion(bundle.version)
        }

        return bundle
    }

    func suggestedFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(AppIdentity.displayName)-Credentials-\(formatter.string(from: now)).json"
    }

    private static func isSupportedBundleType(_ type: String) -> Bool {
        AppIdentityMigration.acceptsCredentialBundleType(type)
    }

    private func encodeBundle(_ bundle: CredentialTransferBundle) throws -> Data {
        do {
            return try encoder.encode(bundle)
        } catch {
            throw CredentialTransferError.encodingFailed
        }
    }

    private func hasCodexConflict(_ account: TokenAccount, in existingAccounts: [TokenAccount]) -> Bool {
        existingAccounts.contains { existing in
            if existing.storageKey == account.storageKey {
                return true
            }
            return existing.matches(accountId: account.accountId, loginIdentity: account.loginIdentity)
        }
    }

    private func hasAntigravityConflict(_ account: AntigravityAccount, in existingAccounts: [AntigravityAccount]) -> Bool {
        existingAccounts.contains { existing in
            if existing.id == account.id {
                return true
            }
            return existing.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private func codexDetail(for account: TokenAccount) -> String {
        let orgName = account.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountLabel = String(account.accountId.prefix(8))
        if let orgName, !orgName.isEmpty {
            return "\(orgName) · \(accountLabel)"
        }
        return accountLabel
    }

    private func antigravityDetail(for account: AntigravityAccount) -> String {
        let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty, name.lowercased() != account.email.lowercased() {
            return name
        }
        return account.tierLabel
    }
}

enum CredentialTransferError: LocalizedError {
    case encodingFailed
    case invalidFormat
    case unsupportedVersion(Int)
    case emptySelection
    case emptyBundle

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return L.credentialsExportFailed
        case .invalidFormat:
            return L.credentialsInvalidBundle
        case .unsupportedVersion(let version):
            return L.credentialsUnsupportedBundleVersion(version)
        case .emptySelection:
            return L.credentialsNoAccountsSelected
        case .emptyBundle:
            return L.credentialsBundleEmpty
        }
    }
}
