import Combine
import Foundation

class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published var accounts: [TokenAccount] = []
    @Published var lastStorageError: String?

    private let repository: AccountPoolRepository
    private let authResolver: CodexAuthResolver
    private let fileManager: FileManager
    private let paths: CodexPaths

    private var directoryMonitors: [DirectoryMonitor] = []
    private var pendingReloadWorkItem: DispatchWorkItem?

    private init(
        repository: AccountPoolRepository = .shared,
        authResolver: CodexAuthResolver = .shared,
        fileManager: FileManager = .default,
        paths: CodexPaths = CodexPathResolver.resolve()
    ) {
        self.repository = repository
        self.authResolver = authResolver
        self.fileManager = fileManager
        self.paths = paths

        try? SecureFileWriter.createPrivateDirectory(at: paths.defaultCodexHomeURL, fileManager: fileManager)
        load()
        startMonitoringExternalChanges()
    }

    func load() {
        switch repository.load() {
        case .success(let loadedAccounts):
            lastStorageError = nil
            accounts = loadedAccounts
            syncActiveAccount(saveIfChanged: false)
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

    func addOrUpdate(_ account: TokenAccount) {
        if let index = matchingIndex(for: account) {
            accounts[index] = mergedAccount(current: accounts[index], incoming: account)
        } else {
            accounts.append(account)
        }
        save()
    }

    func remove(_ account: TokenAccount) {
        let removedActiveAccount = account.isActive
        accounts.removeAll { $0.storageKey == account.storageKey }
        save(allowEmptyOverwrite: accounts.isEmpty)

        if removedActiveAccount {
            syncActiveAccount(saveIfChanged: false)
        }
    }

    func activate(_ account: TokenAccount) throws {
        try authResolver.writeActiveAuth(for: account)
        markActiveAccount()
    }

    func activeAccount() -> TokenAccount? {
        accounts.first { $0.isActive }
    }

    func markActiveAccount() {
        reloadFromDiskIfNeeded()
        guard !accounts.isEmpty else { return }
        syncActiveAccount(saveIfChanged: true)
    }

    func refreshCredentials(for account: TokenAccount) async throws -> TokenAccount {
        let refreshed = try await authResolver.refreshTokens(for: account)
        return try await MainActor.run {
            try persistRefreshedAccount(refreshed, replacing: account)
        }
    }

    func exportActiveStorageKey() -> String? {
        reloadFromDiskIfNeeded()
        syncActiveAccount(saveIfChanged: false)
        return activeAccount()?.storageKey
    }

    func applyImportedAccounts(
        _ importedAccounts: [TokenAccount],
        conflictActions: [String: CredentialImportConflictAction]
    ) throws -> CredentialImportApplySummary {
        guard !importedAccounts.isEmpty else { return CredentialImportApplySummary() }

        reloadFromDiskIfNeeded()

        var mergedAccounts = accounts
        var summary = CredentialImportApplySummary()

        for importedAccount in importedAccounts {
            if let index = matchingIndex(for: importedAccount, in: mergedAccounts) {
                switch conflictActions[importedAccount.storageKey] ?? .overwrite {
                case .overwrite:
                    var incoming = importedAccount
                    incoming.isActive = false
                    mergedAccounts[index] = mergedAccount(current: mergedAccounts[index], incoming: incoming)
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
        try saveThrowing()
        syncActiveAccount(saveIfChanged: false)
        return summary
    }

    private func saveThrowing(allowEmptyOverwrite: Bool = false) throws {
        try repository.save(accounts, allowEmptyOverwrite: allowEmptyOverwrite)
        lastStorageError = nil
    }

    private func reloadFromDiskIfNeeded() {
        guard accounts.isEmpty else { return }
        switch repository.load() {
        case .success(let loadedAccounts):
            guard !loadedAccounts.isEmpty else { return }
            accounts = loadedAccounts
            lastStorageError = nil
        case .failure(let error):
            lastStorageError = error.localizedDescription
        }
    }

    private func persistRefreshedAccount(_ refreshed: TokenAccount, replacing previous: TokenAccount) throws -> TokenAccount {
        var merged = refreshed

        if let index = matchingIndex(for: previous) ?? matchingIndex(for: refreshed) {
            merged.isActive = accounts[index].isActive || previous.isActive || refreshed.isActive
            accounts[index] = mergedAccount(current: accounts[index], incoming: merged)
        } else {
            accounts.append(merged)
        }

        try saveThrowing()

        if shouldRewriteActiveAuth(previous: previous, refreshed: merged) {
            try authResolver.writeActiveAuth(for: merged)
        }

        return merged
    }

    private func shouldRewriteActiveAuth(previous: TokenAccount, refreshed: TokenAccount) -> Bool {
        if previous.isActive || refreshed.isActive {
            return true
        }

        switch authResolver.loadActiveAuth() {
        case .success(let snapshot?):
            return previous.matches(accountId: snapshot.accountId, loginIdentity: snapshot.loginIdentity)
                || refreshed.matches(accountId: snapshot.accountId, loginIdentity: snapshot.loginIdentity)
        case .success(nil):
            return false
        case .failure(let error):
            lastStorageError = error.localizedDescription
            return false
        }
    }

    private func mergedAccount(current: TokenAccount, incoming: TokenAccount) -> TokenAccount {
        var merged = incoming
        merged.isActive = current.isActive || incoming.isActive
        if merged.organizationName == nil {
            merged.organizationName = current.organizationName
        }
        if merged.lastChecked == nil {
            merged.lastChecked = current.lastChecked
        }
        if merged.usageSnapshot == nil {
            merged.usageSnapshot = current.usageSnapshot
        }
        return merged
    }

    private func matchingIndex(for account: TokenAccount) -> Int? {
        matchingIndex(for: account, in: accounts)
    }

    private func matchingIndex(for account: TokenAccount, in accounts: [TokenAccount]) -> Int? {
        if let exactMatch = accounts.firstIndex(where: { $0.storageKey == account.storageKey }) {
            return exactMatch
        }

        return accounts.firstIndex {
            $0.matches(accountId: account.accountId, loginIdentity: account.loginIdentity)
        }
    }

    private func syncActiveAccount(saveIfChanged: Bool) {
        let snapshot: CodexAuthSnapshot?
        switch authResolver.loadActiveAuth() {
        case .success(let activeSnapshot):
            snapshot = activeSnapshot
            lastStorageError = nil
        case .failure(let error):
            lastStorageError = error.localizedDescription
            return
        }

        guard let snapshot else { return }

        let previous = accounts.map(\.isActive)
        for index in accounts.indices {
            accounts[index].isActive = accounts[index].matches(
                accountId: snapshot.accountId,
                loginIdentity: snapshot.loginIdentity
            )
        }

        if saveIfChanged, previous != accounts.map(\.isActive) {
            save()
        }
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
        var seen = Set<String>()
        var result: [URL] = []

        let candidates = [repository.poolURL.deletingLastPathComponent()] + authResolver.readCandidates.map {
            $0.deletingLastPathComponent()
        }

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
            guard let self else { return }
            self.load()
            self.markActiveAccount()
        }
        pendingReloadWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}
