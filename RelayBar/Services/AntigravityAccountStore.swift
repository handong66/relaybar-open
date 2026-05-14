import Combine
import Foundation

class AntigravityAccountStore: ObservableObject {
    static let shared = AntigravityAccountStore()

    @Published var accounts: [AntigravityAccount] = []
    @Published var lastStorageError: String?

    private let repository: AntigravityAccountRepository
    private let tokenRefresher: AntigravityTokenRefresher
    private let switcher: AntigravitySwitcher
    private let importer: AntigravityAccountImporter
    private let fileManager: FileManager
    private let paths: AntigravityPaths

    private var currentAccountId: String?
    private var directoryMonitors: [DirectoryMonitor] = []
    private var pendingReloadWorkItem: DispatchWorkItem?

    private init(
        repository: AntigravityAccountRepository = .shared,
        tokenRefresher: AntigravityTokenRefresher = .shared,
        switcher: AntigravitySwitcher = .shared,
        importer: AntigravityAccountImporter = .shared,
        fileManager: FileManager = .default,
        paths: AntigravityPaths = AntigravityPathResolver.resolve()
    ) {
        self.repository = repository
        self.tokenRefresher = tokenRefresher
        self.switcher = switcher
        self.importer = importer
        self.fileManager = fileManager
        self.paths = paths

        try? SecureFileWriter.createPrivateDirectory(at: paths.codexHomeURL, fileManager: fileManager)
        load()
        startMonitoringExternalChanges()
    }

    func load() {
        switch repository.load() {
        case .success(let pool):
            lastStorageError = nil
            currentAccountId = pool.currentAccountId
            let repair = Self.repairLocalSwitchState(in: pool.accounts)
            accounts = repair.accounts
            markActiveAccount(saveIfChanged: false)
            if repair.changed {
                save()
            }
        case .failure(let error):
            lastStorageError = error.localizedDescription
        }
    }

    func save(allowEmptyOverwrite: Bool = false) {
        do {
            try saveThrowing(allowEmptyOverwrite: allowEmptyOverwrite)
        } catch {
            lastStorageError = error.localizedDescription
        }
    }

    func addOrUpdate(_ account: AntigravityAccount, makeActive: Bool = false) {
        var updated = account
        if let index = matchingIndex(for: account) {
            let current = accounts[index]
            updated.id = current.id
            updated.isActive = makeActive || current.isActive || account.isActive
            if updated.deviceProfile == nil {
                updated.deviceProfile = current.deviceProfile
            }
            if updated.localStateSnapshot == nil {
                updated.localStateSnapshot = current.localStateSnapshot
            }
            if updated.quota == nil {
                updated.quota = current.quota
            }
            if updated.lastChecked == nil {
                updated.lastChecked = current.lastChecked
            }
            updated.createdAt = current.createdAt
            accounts[index] = updated
        } else {
            updated.isActive = makeActive || account.isActive
            accounts.append(updated)
        }

        if makeActive || updated.isActive {
            currentAccountId = updated.id
            markActiveAccount(saveIfChanged: false)
        }

        save()
    }

    func remove(_ account: AntigravityAccount) {
        let removedActiveAccount = account.isActive || currentAccountId == account.id
        accounts.removeAll { $0.id == account.id }
        if removedActiveAccount {
            currentAccountId = accounts.first?.id
            markActiveAccount(saveIfChanged: false)
        }
        save(allowEmptyOverwrite: accounts.isEmpty)
    }

    func activeAccount() -> AntigravityAccount? {
        accounts.first { $0.isActive }
    }

    func markActiveAccount(saveIfChanged: Bool = true) {
        guard !accounts.isEmpty else { return }

        let previous = accounts.map(\.isActive)
        for index in accounts.indices {
            accounts[index].isActive = currentAccountId != nil && accounts[index].id == currentAccountId
        }

        if saveIfChanged, previous != accounts.map(\.isActive) {
            save()
        }
    }

    func activate(_ account: AntigravityAccount) async throws -> String {
        var workingAccount = account

        if workingAccount.accessTokenNeedsRefresh {
            workingAccount = try await tokenRefresher.refresh(account: workingAccount)
        }

        workingAccount.tokenExpired = false
        workingAccount.disabled = false
        workingAccount.disabledReason = nil

        let message = try await switcher.switchToAccount(workingAccount)
        let switchedAccount = workingAccount
        await MainActor.run {
            currentAccountId = switchedAccount.id
            if let index = matchingIndex(for: switchedAccount) {
                accounts[index].lastUsed = Date()
                accounts[index].tokenExpired = false
                accounts[index].disabled = false
            }
            markActiveAccount(saveIfChanged: false)
            save()
        }
        return message
    }

    func refreshCredentials(for account: AntigravityAccount) async throws -> AntigravityAccount {
        let refreshedAccount = try await tokenRefresher.refresh(account: account)
        return await MainActor.run {
            var updated = refreshedAccount
            updated.tokenExpired = false
            updated.disabled = false
            persist(updated, replacing: account)
            return updated
        }
    }

    func importCurrentLogin() async throws -> AntigravityAccount {
        let imported = try await importer.importCurrentLogin()
        await MainActor.run {
            addOrUpdate(imported, makeActive: true)
        }
        return imported
    }

    func currentLoginState() throws -> ImportedAntigravityOAuthState {
        guard fileManager.fileExists(atPath: paths.stateDatabaseURL.path) else {
            throw AntigravitySwitchError.databaseMissing(paths.stateDatabaseURL.path)
        }
        return try AntigravityAccountImporter.extractCurrentLoginState(from: paths.stateDatabaseURL)
    }

    func reauthorizeFromCurrentLogin(_ account: AntigravityAccount) async throws -> AntigravityAccount {
        let imported = try await importer.importCurrentLogin()
        let matchesSelectedAccount = Self.normalizedEmail(imported.email) == Self.normalizedEmail(account.email)
            || Self.sameRefreshToken(imported.token.refreshToken, account.token.refreshToken)
        guard matchesSelectedAccount else {
            throw AntigravityCurrentLoginReauthError.emailMismatch(
                expected: account.displayName,
                actual: imported.displayName
            )
        }

        var updated = imported
        updated.id = account.id
        updated.isActive = account.isActive
        updated.quota = account.quota
        updated.deviceProfile = imported.deviceProfile ?? account.deviceProfile
        updated.createdAt = account.createdAt
        updated.lastChecked = account.lastChecked

        updated.tokenExpired = false
        updated.disabled = false
        updated.disabledReason = nil
        updated.validationBlocked = false
        updated.validationBlockedReason = nil

        let updatedAccount = updated
        return await MainActor.run {
            addOrUpdate(updatedAccount, makeActive: account.isActive)
            return accounts.first { Self.normalizedEmail($0.email) == Self.normalizedEmail(updatedAccount.email) }
                ?? updatedAccount
        }
    }

    func exportPoolSnapshot() -> AntigravityAccountPool {
        return AntigravityAccountPool(
            currentAccountId: currentAccountId,
            accounts: accounts
        )
    }

    func applyImportedPool(
        _ importedPool: AntigravityAccountPool,
        conflictActions: [String: CredentialImportConflictAction]
    ) -> CredentialImportApplySummary {
        guard !importedPool.accounts.isEmpty else { return CredentialImportApplySummary() }

        var mergedAccounts = accounts
        let resolvedActiveId = currentAccountId
        var summary = CredentialImportApplySummary()

        for importedAccount in importedPool.accounts {
            if let index = matchingIndex(for: importedAccount, in: mergedAccounts) {
                switch conflictActions[importedAccount.id] ?? .overwrite {
                case .overwrite:
                    var incoming = importedAccount
                    incoming.isActive = false
                    let mergedAccount = mergedAccount(current: mergedAccounts[index], incoming: incoming)
                    mergedAccounts[index] = mergedAccount
                    summary.overwrittenCount += 1
                case .keepLocal:
                    summary.skippedCount += 1
                }
            } else {
                var incoming = importedAccount
                incoming.isActive = false
                mergedAccounts.append(incoming)
                summary.addedCount += 1
            }
        }

        accounts = mergedAccounts
        currentAccountId = resolvedActiveId
        if let resolvedActiveId {
            for index in accounts.indices {
                accounts[index].isActive = accounts[index].id == resolvedActiveId
            }
        }
        save()
        return summary
    }

    private func persist(_ account: AntigravityAccount, replacing previous: AntigravityAccount) {
        if let index = matchingIndex(for: previous) ?? matchingIndex(for: account) {
            var merged = mergedAccount(current: accounts[index], incoming: account)
            merged.isActive = accounts[index].isActive || account.isActive || previous.isActive
            accounts[index] = merged
        } else {
            accounts.append(account)
        }

        if account.isActive || previous.isActive {
            currentAccountId = account.id
            markActiveAccount(saveIfChanged: false)
        }

        try? saveThrowing()
    }

    private func saveThrowing(allowEmptyOverwrite: Bool = false) throws {
        try repository.save(
            AntigravityAccountPool(
                currentAccountId: currentAccountId,
                accounts: accounts
            ),
            allowEmptyOverwrite: allowEmptyOverwrite
        )
        lastStorageError = nil
    }

    private func mergedAccount(current: AntigravityAccount, incoming: AntigravityAccount) -> AntigravityAccount {
        var merged = incoming
        merged.id = current.id
        merged.isActive = current.isActive || incoming.isActive
        if merged.deviceProfile == nil {
            merged.deviceProfile = current.deviceProfile
        }
        if merged.localStateSnapshot == nil {
            merged.localStateSnapshot = current.localStateSnapshot
        }
        if merged.quota == nil {
            merged.quota = current.quota
        }
        if merged.lastChecked == nil {
            merged.lastChecked = current.lastChecked
        }
        if merged.name == nil {
            merged.name = current.name
        }
        merged.createdAt = current.createdAt
        return merged
    }

    private func matchingIndex(for account: AntigravityAccount) -> Int? {
        matchingIndex(for: account, in: accounts)
    }

    private func matchingIndex(for account: AntigravityAccount, in accounts: [AntigravityAccount]) -> Int? {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            return index
        }

        return accounts.firstIndex {
            Self.normalizedEmail($0.email) == Self.normalizedEmail(account.email)
        }
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sameRefreshToken(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return !left.isEmpty && left == right
    }

    struct LocalSwitchStateRepair {
        let accounts: [AntigravityAccount]
        let changed: Bool
    }

    static func repairLocalSwitchState(in accounts: [AntigravityAccount]) -> LocalSwitchStateRepair {
        var changed = false
        let repaired = accounts.map { account -> AntigravityAccount in
            guard account.tokenExpired, account.canSwitchLocally else {
                return account
            }

            var updated = account
            updated.tokenExpired = false
            changed = true
            return updated
        }

        return LocalSwitchStateRepair(accounts: repaired, changed: changed)
    }

    private func startMonitoringExternalChanges() {
        let directories = uniqueDirectoriesToWatch()
        directoryMonitors = directories.compactMap { directory in
            DirectoryMonitor(url: directory) { [weak self] in
                self?.scheduleReloadAfterExternalChange()
            }
        }
    }

    private func uniqueDirectoriesToWatch() -> [URL] {
        let candidates = [
            repository.poolURL.deletingLastPathComponent(),
            paths.antigravityGlobalStorageURL
        ]

        var seen = Set<String>()
        var result: [URL] = []
        for candidate in candidates.map(\.standardizedFileURL) {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard seen.insert(candidate.path).inserted else { continue }
            result.append(candidate)
        }

        return result
    }

    private func scheduleReloadAfterExternalChange() {
        pendingReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.load()
        }
        pendingReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}

enum AntigravityCurrentLoginReauthError: LocalizedError {
    case emailMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .emailMismatch(let expected, let actual):
            return L.antigravityCurrentLoginMismatch(expected: expected, actual: actual)
        }
    }
}
