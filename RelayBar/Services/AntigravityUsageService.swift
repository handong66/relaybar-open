import Foundation

final class AntigravityUsageService {
    static let shared = AntigravityUsageService()

    private let usageClient: AntigravityUsageClient

    init(usageClient: AntigravityUsageClient = .shared) {
        self.usageClient = usageClient
    }

    @discardableResult
    func refreshOne(account: AntigravityAccount, store: AntigravityAccountStore) async -> String? {
        await refreshAccount(account, store: store)
    }

    @discardableResult
    func refreshAll(store: AntigravityAccountStore) async -> String? {
        do {
            let account = try await store.importCurrentLogin()
            guard !account.accessTokenNeedsRefresh else {
                return L.antigravityCurrentLoginImported
            }
            return await refreshAccount(account, store: store)
        } catch {
            return error.localizedDescription
        }
    }

    private func refreshAccount(_ account: AntigravityAccount, store: AntigravityAccountStore) async -> String? {
        var workingAccount = account

        if workingAccount.accessTokenNeedsRefresh {
            do {
                workingAccount = try await store.refreshCredentials(for: workingAccount)
            } catch AntigravityOAuthError.missingOAuthConfiguration {
                return L.antigravityRefreshNeedsCurrentLogin
            } catch {
                return error.localizedDescription
            }
        }

        let firstAttempt = await usageClient.fetchSnapshot(for: workingAccount)
        switch firstAttempt {
        case .tokenExpired:
            do {
                workingAccount = try await store.refreshCredentials(for: workingAccount)
            } catch AntigravityOAuthError.missingOAuthConfiguration {
                await markTokenExpired(account: workingAccount, store: store, reason: L.antigravityRefreshNeedsCurrentLogin)
                return L.antigravityRefreshNeedsCurrentLogin
            } catch {
                await markTokenExpired(account: workingAccount, store: store, reason: error.localizedDescription)
                return error.localizedDescription
            }

            let secondAttempt = await usageClient.fetchSnapshot(for: workingAccount)
            return await handle(result: secondAttempt, account: workingAccount, store: store)
        default:
            return await handle(result: firstAttempt, account: workingAccount, store: store)
        }
    }

    private func handle(
        result: AntigravityUsageFetchResult,
        account: AntigravityAccount,
        store: AntigravityAccountStore
    ) async -> String? {
        switch result {
        case .success(let snapshot):
            await apply(snapshot: snapshot, to: account, store: store)
            return nil
        case .tokenExpired:
            await markTokenExpired(account: account, store: store, reason: nil)
            return "Antigravity Token 已过期，请重新授权或重新导入"
        case .forbidden(let reason):
            await markForbidden(account: account, store: store, reason: reason)
            return nil
        case .retryableFailure(let message):
            return message
        case .parseFailure:
            return "Antigravity 额度响应解析失败"
        }
    }

    private func apply(
        snapshot: AntigravityUsageSnapshot,
        to account: AntigravityAccount,
        store: AntigravityAccountStore
    ) async {
        await MainActor.run {
            var updated = account
            updated.quota = snapshot.quota
            if let projectId = snapshot.projectId, !projectId.isEmpty {
                updated.token.projectId = projectId
            }
            updated.lastChecked = Date()
            updated.tokenExpired = false
            updated.disabled = false
            updated.disabledReason = nil
            store.addOrUpdate(updated)
        }
    }

    private func markForbidden(
        account: AntigravityAccount,
        store: AntigravityAccountStore,
        reason: String?
    ) async {
        await MainActor.run {
            var updated = account
            updated.quota = AntigravityQuotaData(
                models: account.quota?.models ?? [],
                lastUpdated: Date(),
                isForbidden: true,
                forbiddenReason: reason,
                subscriptionTier: account.quota?.subscriptionTier
            )
            updated.tokenExpired = false
            updated.disabled = false
            store.addOrUpdate(updated)
        }
    }

    private func markTokenExpired(
        account: AntigravityAccount,
        store: AntigravityAccountStore,
        reason: String?
    ) async {
        await MainActor.run {
            var updated = account
            updated.tokenExpired = true
            updated.disabled = false
            updated.disabledReason = reason
            store.addOrUpdate(updated)
        }
    }
}
