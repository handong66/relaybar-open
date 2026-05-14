import Foundation

class WhamService {
    static let shared = WhamService()

    private let usageClient: CodexUsageClient

    init(usageClient: CodexUsageClient = .shared) {
        self.usageClient = usageClient
    }

    @discardableResult
    func refreshOne(account: TokenAccount, store: TokenStore) async -> String? {
        await refreshAccount(account, store: store)
    }

    @discardableResult
    func refreshAll(store: TokenStore) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for account in store.accounts {
                group.addTask {
                    await self.refreshAccount(account, store: store)
                }
            }

            var firstError: String?
            for await message in group {
                if firstError == nil, let message, !message.isEmpty {
                    firstError = message
                }
            }
            return firstError
        }
    }

    private func refreshAccount(_ account: TokenAccount, store: TokenStore) async -> String? {
        var workingAccount = account

        if workingAccount.accessTokenNeedsRefresh {
            do {
                workingAccount = try await store.refreshCredentials(for: workingAccount)
            } catch {
                await markTokenExpired(account: workingAccount, store: store)
                return error.localizedDescription
            }
        }

        let firstAttempt = await usageClient.fetchSnapshot(for: workingAccount)
        switch firstAttempt {
        case .tokenExpired:
            do {
                workingAccount = try await store.refreshCredentials(for: workingAccount)
            } catch {
                await markTokenExpired(account: workingAccount, store: store)
                return error.localizedDescription
            }

            let secondAttempt = await usageClient.fetchSnapshot(for: workingAccount)
            return await handle(result: secondAttempt, account: workingAccount, store: store)

        default:
            return await handle(result: firstAttempt, account: workingAccount, store: store)
        }
    }

    private func handle(
        result: CodexUsageFetchResult,
        account: TokenAccount,
        store: TokenStore
    ) async -> String? {
        switch result {
        case .success(let snapshot):
            await apply(snapshot: snapshot, to: account, store: store)
            return nil
        case .tokenExpired:
            await markTokenExpired(account: account, store: store)
            return "Token 已过期，请重新授权或稍后重试"
        case .suspended:
            await markSuspended(account: account, store: store)
            return nil
        case .retryableFailure(let message):
            return message
        case .parseFailure:
            return "用量响应解析失败"
        }
    }

    private func apply(
        snapshot: CodexUsageSnapshot,
        to account: TokenAccount,
        store: TokenStore
    ) async {
        await MainActor.run {
            var updated = account
            updated.planType = snapshot.planType
            updated.primaryUsedPercent = snapshot.primaryUsedPercent
            updated.secondaryUsedPercent = snapshot.secondaryUsedPercent
            updated.primaryResetAt = snapshot.primaryResetAt
            updated.secondaryResetAt = snapshot.secondaryResetAt
            updated.lastChecked = Date()
            updated.tokenExpired = false
            updated.isSuspended = false
            updated.usageSnapshot = snapshot.usageSnapshot
            if let organizationName = snapshot.organizationName, !organizationName.isEmpty {
                updated.organizationName = organizationName
            }
            store.addOrUpdate(updated)
        }
    }

    private func markSuspended(account: TokenAccount, store: TokenStore) async {
        await MainActor.run {
            var updated = account
            updated.isSuspended = true
            updated.tokenExpired = false
            store.addOrUpdate(updated)
        }
    }

    private func markTokenExpired(account: TokenAccount, store: TokenStore) async {
        await MainActor.run {
            var updated = account
            updated.tokenExpired = true
            updated.isSuspended = false
            store.addOrUpdate(updated)
        }
    }
}

struct WhamUsageResult {
    let planType: String
    let primaryUsedPercent: Double
    let secondaryUsedPercent: Double
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let usageSnapshot: UsageSnapshot?
}
