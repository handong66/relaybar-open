import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private enum MenuProvider: String, CaseIterable, Identifiable {
    case codex
    case antigravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return L.providerCodex
        case .antigravity: return L.providerAntigravity
        }
    }
}

private struct MenuHeaderNotice {
    let message: String
    let tone: MenuNoticeTone
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var store: TokenStore
    @EnvironmentObject var oauth: OAuthManager
    @EnvironmentObject var antigravityStore: AntigravityAccountStore
    @EnvironmentObject var antigravityOAuth: AntigravityOAuthManager
    @StateObject private var credentialTransferWindowModel = CredentialTransferWindowModel.shared

    @State private var selectedProvider: MenuProvider = .codex
    @State private var isRefreshing = false
    @State private var isAntigravityRefreshing = false
    @State private var showError: String?
    @State private var now = Date()
    @State private var refreshingAccounts: Set<String> = []
    @State private var refreshingAntigravityAccounts: Set<String> = []
    @State private var menuVisible = false
    @State private var languageToggle = false
    @State private var languageRefreshToken = 0
    @State private var localUsageSnapshot: LocalUsageSnapshot?
    @State private var showsAllCodexAccounts = false
    @State private var showsAllAntigravityAccounts = false

    private let countdownTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let quickTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let slowTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    private let maxVisibleSecondaryAccounts = 3
    private let estimatedHeroHeight: CGFloat = 270
    private let estimatedSecondaryHeight: CGFloat = 104
    private let listVerticalPadding: CGFloat = 16
    private let maxListHeight: CGFloat = 420

    private var renderedAccounts: [TokenAccount] {
        guard let localUsageSnapshot, let activeAccount = store.activeAccount() else {
            return store.accounts
        }

        return store.accounts.map { account in
            var rendered = account
            if account.matches(accountId: activeAccount.accountId, loginIdentity: activeAccount.loginIdentity) {
                rendered.localUsageSnapshot = localUsageSnapshot
            } else {
                rendered.localUsageSnapshot = nil
            }
            return rendered
        }
    }

    private var panelState: AccountPanelState {
        AccountPanelState(
            accounts: renderedAccounts,
            maxVisibleSecondaryAccounts: maxVisibleSecondaryAccounts,
            estimatedHeroHeight: estimatedHeroHeight,
            estimatedSecondaryHeight: estimatedSecondaryHeight,
            listVerticalPadding: listVerticalPadding
        )
    }

    private var orderedAntigravityAccounts: [AntigravityAccount] {
        antigravityStore.accounts.sorted { lhs, rhs in
            let left = antigravitySortKey(lhs)
            let right = antigravitySortKey(rhs)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            if left.2 != right.2 { return left.2 > right.2 }
            return lhs.email < rhs.email
        }
    }

    private var activeAntigravityAccount: AntigravityAccount? {
        orderedAntigravityAccounts.first
    }

    private var antigravitySecondaryAccounts: [AntigravityAccount] {
        Array(orderedAntigravityAccounts.dropFirst())
    }

    private var visibleAntigravitySecondaryAccounts: [AntigravityAccount] {
        if showsAllAntigravityAccounts {
            return antigravitySecondaryAccounts
        }
        return Array(antigravitySecondaryAccounts.prefix(maxVisibleSecondaryAccounts))
    }

    private var hiddenAntigravityCount: Int {
        max(antigravitySecondaryAccounts.count - visibleAntigravitySecondaryAccounts.count, 0)
    }

    private var selectedAccountCount: Int {
        selectedProvider == .codex ? store.accounts.count : antigravityStore.accounts.count
    }

    private var selectedAvailableCount: Int {
        selectedProvider == .codex
            ? panelState.availableCount
            : antigravityStore.accounts.filter(\.isAvailable).count
    }

    private var selectedLatestUpdate: Date? {
        switch selectedProvider {
        case .codex:
            return panelState.latestUpdate
        case .antigravity:
            return antigravityStore.accounts.compactMap(\.lastChecked).max()
        }
    }

    private var selectedIsRefreshing: Bool {
        selectedProvider == .codex ? isRefreshing : isAntigravityRefreshing
    }

    private var headerSummaryText: String {
        ProviderSummaryState.subtitle(
            provider: selectedProvider == .codex ? .codex : .antigravity,
            accountCount: selectedAccountCount,
            isRefreshing: selectedIsRefreshing
        ) ?? ""
    }

    private var headerNotice: MenuHeaderNotice? {
        if let showError, !showError.isEmpty {
            return MenuHeaderNotice(message: showError, tone: .critical)
        }
        if let completion = credentialTransferWindowModel.completionMessage, !completion.isEmpty {
            return MenuHeaderNotice(message: completion, tone: .positive)
        }
        return nil
    }

    var body: some View {
        MenuPanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                MenuBarHeader(
                    provider: $selectedProvider,
                    accountCount: selectedAccountCount,
                    availableCount: selectedAvailableCount,
                    isRefreshing: selectedIsRefreshing,
                    summaryText: headerSummaryText,
                    lastUpdateText: selectedLatestUpdate.map(relativeTime),
                    notice: headerNotice,
                    onDismissNotice: dismissHeaderNotice,
                    onRefresh: { Task { await refreshSelected(showErrors: true) } }
                )

                providerBody

                Divider()

                MenuBarFooter(
                    languageLabel: currentLanguageLabel,
                    showsImportCurrentLogin: selectedProvider == .antigravity,
                    showsConfigureOAuth: false,
                    onAddAccount: addSelectedAccount,
                    onConfigureOAuth: openAntigravityOAuthConfig,
                    onImportCurrentLogin: importCurrentAntigravityLogin,
                    onExportCredentials: exportCredentialBundle,
                    onImportCredentials: importCredentialBundle,
                    onToggleLanguage: toggleLanguage,
                    onQuit: { NSApplication.shared.terminate(nil) }
                )
            }
        }
        .id(languageRefreshToken)
        .frame(width: MenuDesignTokens.panelWidth)
        .onReceive(countdownTimer) { _ in
            now = Date()
            syncStoreErrorBanner()
        }
        .onReceive(quickTimer) { _ in
            guard menuVisible else { return }
            reloadVisibleProviderFromDisk()
            syncStoreErrorBanner()

            switch selectedProvider {
            case .codex:
                guard let active = store.activeAccount(), !active.secondaryExhausted else { return }
                Task { await refreshAccount(active, showErrors: false) }
            case .antigravity:
                guard let active = antigravityStore.activeAccount(), !active.tokenExpired else { return }
                Task { await refreshAntigravityAccount(active, showErrors: false) }
            }
        }
        .onReceive(slowTimer) { _ in
            Task {
                if !menuVisible {
                    store.load()
                    antigravityStore.load()
                    await refreshSelected(showErrors: false)
                } else if selectedProvider == .codex {
                    await refreshLocalUsage(forceRefresh: false)
                }
                store.markActiveAccount()
                antigravityStore.markActiveAccount()
                syncStoreErrorBanner()
            }
        }
        .onChange(of: selectedProvider) {
            showsAllCodexAccounts = false
            showsAllAntigravityAccounts = false
        }
        .onAppear {
            menuVisible = true
            reloadVisibleProviderFromDisk()
            Task { await refreshLocalUsage(forceRefresh: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            languageRefreshToken += 1
        }
        .onDisappear {
            menuVisible = false
        }
    }

    private var providerBody: some View {
        Group {
            switch selectedProvider {
            case .codex:
                codexAccountList
            case .antigravity:
                antigravityAccountList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var codexAccountList: some View {
        Group {
            if renderedAccounts.isEmpty {
                MenuBarEmptyState(
                    provider: .codex,
                    onAddAccount: addSelectedAccount,
                    onImportCredentials: importCredentialBundle,
                    onImportCurrentLogin: nil,
                    onConfigureOAuth: nil
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let hero = panelState.activeAccount {
                            VStack(alignment: .leading, spacing: 10) {
                                MenuSectionHeading(title: L.menuCurrentAccountTitle, detail: nil)
                                AccountRowView(
                                    account: hero,
                                    role: .hero,
                                    isActive: hero.isActive,
                                    isRefreshing: refreshingAccounts.contains(hero.id)
                                ) {
                                    activateAccount(hero)
                                } onRefresh: {
                                    Task { await refreshAccount(hero, showErrors: true) }
                                } onReauth: {
                                    reauthAccount(hero)
                                } onDelete: {
                                    store.remove(hero)
                                    syncStoreErrorBanner()
                                }
                            }
                        }

                        if !panelState.secondaryAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    MenuSectionHeading(
                                        title: L.menuOtherAccountsTitle,
                                        detail: "\(panelState.secondaryAccounts.count)"
                                    )

                                    Spacer()

                                    if panelState.hiddenSecondaryCount > 0 || showsAllCodexAccounts {
                                        Button(showsAllCodexAccounts ? L.menuShowLessAccounts : L.menuShowMoreAccounts(panelState.hiddenSecondaryCount)) {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                showsAllCodexAccounts.toggle()
                                            }
                                        }
                                        .buttonStyle(MenuSecondaryButtonStyle())
                                    }
                                }

                                VStack(spacing: 8) {
                                    ForEach(showsAllCodexAccounts ? panelState.secondaryAccounts : panelState.visibleSecondaryAccounts) { account in
                                        AccountRowView(
                                            account: account,
                                            role: .secondary,
                                            isActive: account.isActive,
                                            isRefreshing: refreshingAccounts.contains(account.id)
                                        ) {
                                            activateAccount(account)
                                        } onRefresh: {
                                            Task { await refreshAccount(account, showErrors: true) }
                                        } onReauth: {
                                            reauthAccount(account)
                                        } onDelete: {
                                            store.remove(account)
                                            syncStoreErrorBanner()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(codexListHeight, maxListHeight))
            }
        }
    }

    private var antigravityAccountList: some View {
        Group {
            if antigravityStore.accounts.isEmpty {
                MenuBarEmptyState(
                    provider: .antigravity,
                    onAddAccount: addSelectedAccount,
                    onImportCredentials: importCredentialBundle,
                    onImportCurrentLogin: importCurrentAntigravityLogin,
                    onConfigureOAuth: nil
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let hero = activeAntigravityAccount {
                            VStack(alignment: .leading, spacing: 10) {
                                MenuSectionHeading(title: L.menuCurrentAccountTitle, detail: nil)
                                AntigravityAccountRowView(
                                    account: hero,
                                    role: .hero,
                                    isActive: hero.isActive,
                                    isRefreshing: refreshingAntigravityAccounts.contains(hero.id)
                                ) {
                                    activateAntigravityAccount(hero)
                                } onRefresh: {
                                    Task { await refreshAntigravityAccount(hero, showErrors: true) }
                                } onReauth: {
                                    reauthAntigravityAccount(hero)
                                } onDelete: {
                                    antigravityStore.remove(hero)
                                    syncStoreErrorBanner()
                                }
                            }
                        }

                        if !antigravitySecondaryAccounts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    MenuSectionHeading(
                                        title: L.menuOtherAccountsTitle,
                                        detail: "\(antigravitySecondaryAccounts.count)"
                                    )

                                    Spacer()

                                    if hiddenAntigravityCount > 0 || showsAllAntigravityAccounts {
                                        Button(showsAllAntigravityAccounts ? L.menuShowLessAccounts : L.menuShowMoreAccounts(hiddenAntigravityCount)) {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                showsAllAntigravityAccounts.toggle()
                                            }
                                        }
                                        .buttonStyle(MenuSecondaryButtonStyle())
                                    }
                                }

                                VStack(spacing: 8) {
                                    ForEach(showsAllAntigravityAccounts ? antigravitySecondaryAccounts : visibleAntigravitySecondaryAccounts) { account in
                                        AntigravityAccountRowView(
                                            account: account,
                                            role: .secondary,
                                            isActive: account.isActive,
                                            isRefreshing: refreshingAntigravityAccounts.contains(account.id)
                                        ) {
                                            activateAntigravityAccount(account)
                                        } onRefresh: {
                                            Task { await refreshAntigravityAccount(account, showErrors: true) }
                                        } onReauth: {
                                            reauthAntigravityAccount(account)
                                        } onDelete: {
                                            antigravityStore.remove(account)
                                            syncStoreErrorBanner()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(antigravityListHeight, maxListHeight))
            }
        }
    }

    private var codexListHeight: CGFloat {
        guard !renderedAccounts.isEmpty else { return 164 }
        let secondaryCount = showsAllCodexAccounts ? panelState.secondaryAccounts.count : panelState.visibleSecondaryAccounts.count
        let chromeHeight: CGFloat = panelState.secondaryAccounts.isEmpty ? 40 : 86
        return estimatedHeroHeight + CGFloat(secondaryCount) * estimatedSecondaryHeight + chromeHeight
    }

    private var antigravityListHeight: CGFloat {
        guard !antigravityStore.accounts.isEmpty else { return 176 }
        let secondaryCount = showsAllAntigravityAccounts ? antigravitySecondaryAccounts.count : visibleAntigravitySecondaryAccounts.count
        let chromeHeight: CGFloat = antigravitySecondaryAccounts.isEmpty ? 40 : 86
        return estimatedHeroHeight + CGFloat(secondaryCount) * estimatedSecondaryHeight + chromeHeight
    }

    private var currentLanguageLabel: String {
        L.zh ? "中" : "EN"
    }

    private func dismissHeaderNotice() {
        if showError != nil {
            showError = nil
            return
        }
        credentialTransferWindowModel.clearCompletionMessage()
    }

    private func antigravitySortKey(_ account: AntigravityAccount) -> (Int, Int, TimeInterval) {
        let statusRank: Int
        if account.isActive {
            statusRank = 0
        } else if account.isAvailable {
            statusRank = 1
        } else if account.tokenExpired || account.disabled || account.validationBlocked || account.isForbidden {
            statusRank = 3
        } else {
            statusRank = 2
        }

        return (
            account.isActive ? 0 : 1,
            statusRank,
            account.lastChecked?.timeIntervalSince1970 ?? .zero
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return L.justUpdated }
        if seconds < 3600 { return L.minutesAgo(seconds / 60) }
        return L.hoursAgo(seconds / 3600)
    }

    private func activateAccount(_ account: TokenAccount) {
        do {
            try store.activate(account)
            syncStoreErrorBanner()
        } catch {
            showError = error.localizedDescription
        }
    }

    private func activateAntigravityAccount(_ account: AntigravityAccount) {
        Task {
            refreshingAntigravityAccounts.insert(account.id)
            do {
                let message = try await antigravityStore.activate(account)
                showError = message
            } catch {
                handleAntigravityOAuthFailure(error)
            }
            refreshingAntigravityAccounts.remove(account.id)
        }
    }

    private func refreshSelected(showErrors: Bool) async {
        switch selectedProvider {
        case .codex:
            await refresh(showErrors: showErrors)
        case .antigravity:
            await refreshAntigravity(showErrors: showErrors)
        }
    }

    private func refresh(showErrors: Bool) async {
        isRefreshing = true
        store.load()
        async let refreshError = WhamService.shared.refreshAll(store: store)
        async let refreshedLocalUsage = CodexLocalUsageService.shared.fetchSnapshot(forceRefresh: true)
        let (message, localUsage) = await (refreshError, refreshedLocalUsage)
        localUsageSnapshot = localUsage
        isRefreshing = false
        syncBanner(preferredMessage: message, showErrors: showErrors)
    }

    private func refreshAntigravity(showErrors: Bool) async {
        isAntigravityRefreshing = true
        antigravityStore.load()
        let message = await AntigravityUsageService.shared.refreshAll(store: antigravityStore)
        isAntigravityRefreshing = false
        syncBanner(preferredMessage: message, showErrors: showErrors)
    }

    private func refreshAccount(_ account: TokenAccount, showErrors: Bool) async {
        refreshingAccounts.insert(account.id)
        let refreshError = await WhamService.shared.refreshOne(account: account, store: store)
        if account.isActive {
            localUsageSnapshot = await CodexLocalUsageService.shared.fetchSnapshot(forceRefresh: false)
        }
        refreshingAccounts.remove(account.id)
        syncBanner(preferredMessage: refreshError, showErrors: showErrors)
    }

    private func refreshAntigravityAccount(_ account: AntigravityAccount, showErrors: Bool) async {
        refreshingAntigravityAccounts.insert(account.id)
        let refreshError = await AntigravityUsageService.shared.refreshOne(account: account, store: antigravityStore)
        refreshingAntigravityAccounts.remove(account.id)
        syncBanner(preferredMessage: refreshError, showErrors: showErrors)
    }

    private func reauthAccount(_ account: TokenAccount) {
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                var updated = AccountBuilder.build(from: tokens)
                if updated.storageKey == account.storageKey {
                    updated.isActive = account.isActive
                    updated.tokenExpired = false
                    updated.isSuspended = false
                    updated.primaryUsedPercent = account.primaryUsedPercent
                    updated.secondaryUsedPercent = account.secondaryUsedPercent
                    updated.primaryResetAt = account.primaryResetAt
                    updated.secondaryResetAt = account.secondaryResetAt
                    updated.lastChecked = account.lastChecked
                    updated.organizationName = account.organizationName
                    updated.usageSnapshot = account.usageSnapshot
                }

                store.addOrUpdate(updated)
                if updated.isActive {
                    do {
                        try store.activate(updated)
                    } catch {
                        showError = error.localizedDescription
                    }
                }

                syncStoreErrorBanner()
                Task { await refreshAccount(updated, showErrors: true) }
            case .failure(let error):
                handleAntigravityOAuthFailure(error)
            }
        }
    }

    private func reauthAntigravityAccount(_ account: AntigravityAccount) {
        Task {
            refreshingAntigravityAccounts.insert(account.id)
            do {
                if currentAntigravityLoginMatches(account) {
                    let updated = try await antigravityStore.reauthorizeFromCurrentLogin(account)
                    syncStoreErrorBanner()
                    if updated.accessTokenNeedsRefresh {
                        syncBanner(preferredMessage: L.antigravityCurrentLoginReauthorized, showErrors: true)
                    } else {
                        await refreshAntigravityAccount(updated, showErrors: true)
                    }
                    refreshingAntigravityAccounts.remove(account.id)
                } else {
                    AntigravityProcessController.shared.openAntigravity()
                    syncBanner(preferredMessage: L.antigravityReauthNeedsOfficialLogin(account: account.displayName), showErrors: true)
                    refreshingAntigravityAccounts.remove(account.id)
                }
            } catch {
                handleAntigravityOAuthFailure(error, opensOAuthSetup: false)
                refreshingAntigravityAccounts.remove(account.id)
            }
        }
    }

    private func currentAntigravityLoginMatches(_ account: AntigravityAccount) -> Bool {
        guard let state = try? antigravityStore.currentLoginState() else {
            return false
        }

        if let email = state.email, normalizedEmail(email) == normalizedEmail(account.email) {
            return true
        }

        let currentRefreshToken = state.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountRefreshToken = account.token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentRefreshToken.isEmpty && currentRefreshToken == accountRefreshToken
    }

    private func addSelectedAccount() {
        credentialTransferWindowModel.clearCompletionMessage()
        switch selectedProvider {
        case .codex:
            addAccount()
        case .antigravity:
            importCurrentAntigravityLogin()
        }
    }

    private func addAccount() {
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                let account = AccountBuilder.build(from: tokens)
                store.addOrUpdate(account)
                syncStoreErrorBanner()
                Task { await refreshAccount(account, showErrors: true) }
            case .failure(let error):
                showError = error.localizedDescription
            }
        }
    }

    private func addAntigravityAccount() {
        importCurrentAntigravityLogin()
    }

    private func importCurrentAntigravityLogin() {
        guard selectedProvider == .antigravity else { return }
        credentialTransferWindowModel.clearCompletionMessage()
        Task {
            isAntigravityRefreshing = true
            do {
                let account = try await antigravityStore.importCurrentLogin()
                if account.accessTokenNeedsRefresh {
                    syncBanner(preferredMessage: L.antigravityCurrentLoginImported, showErrors: true)
                } else {
                    let message = await AntigravityUsageService.shared.refreshOne(account: account, store: antigravityStore)
                    syncBanner(preferredMessage: message, showErrors: true)
                }
            } catch {
                handleAntigravityOAuthFailure(error, opensOAuthSetup: false)
            }
            isAntigravityRefreshing = false
        }
    }

    private func exportCredentialBundle() {
        credentialTransferWindowModel.clearCompletionMessage()
        store.markActiveAccount()
        antigravityStore.markActiveAccount()

        let codexAccounts = store.accounts
        let activeCodexStorageKey = store.exportActiveStorageKey()
        let antigravityPool = antigravityStore.exportPoolSnapshot()
        let selectableItems = CredentialTransferService.shared.exportItems(
            codexAccounts: codexAccounts,
            activeCodexStorageKey: activeCodexStorageKey,
            antigravityPool: antigravityPool
        )

        guard !selectableItems.isEmpty else {
            showError = L.noAccounts
            return
        }

        credentialTransferWindowModel.prepareExport(
            codexAccounts: codexAccounts,
            activeCodexStorageKey: activeCodexStorageKey,
            antigravityPool: antigravityPool
        )
        openWindow(id: CredentialTransferWindowModel.windowID)
    }

    private func importCredentialBundle() {
        credentialTransferWindowModel.clearCompletionMessage()
        credentialTransferWindowModel.beginImport()
        openWindow(id: CredentialTransferWindowModel.windowID)
    }

    private func openAntigravityOAuthConfig() {
        openWindow(id: AntigravityOAuthConfigWindowModel.windowID)
    }

    private func handleAntigravityOAuthFailure(_ error: Error, opensOAuthSetup: Bool = true) {
        showError = error.localizedDescription
        guard opensOAuthSetup else { return }
        guard let oauthError = error as? AntigravityOAuthError else { return }
        if case .missingOAuthConfiguration = oauthError {
            openAntigravityOAuthConfig()
        }
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func toggleLanguage() {
        L.languageOverride = L.nextLanguageOverride(
            currentOverride: L.languageOverride,
            resolvedZh: L.zh
        )
        languageToggle.toggle()
    }

    private func reloadVisibleProviderFromDisk() {
        switch selectedProvider {
        case .codex:
            reloadAccountsFromDisk()
        case .antigravity:
            antigravityStore.load()
            antigravityStore.markActiveAccount()
        }
    }

    private func reloadAccountsFromDisk() {
        store.load()
        store.markActiveAccount()
        syncStoreErrorBanner()
    }

    private func refreshLocalUsage(forceRefresh: Bool) async {
        localUsageSnapshot = await CodexLocalUsageService.shared.fetchSnapshot(forceRefresh: forceRefresh)
    }

    private func syncStoreErrorBanner() {
        syncBanner(preferredMessage: nil, showErrors: true)
    }

    private func syncBanner(preferredMessage: String?, showErrors: Bool) {
        let storageError = selectedProvider == .codex
            ? store.lastStorageError
            : antigravityStore.lastStorageError

        if let storageError, !storageError.isEmpty {
            showError = storageError
            return
        }

        if showErrors {
            showError = preferredMessage
        }
    }
}

private struct MenuBarHeader: View {
    @Binding var provider: MenuProvider
    let accountCount: Int
    let availableCount: Int
    let isRefreshing: Bool
    let summaryText: String
    let lastUpdateText: String?
    let notice: MenuHeaderNotice?
    let onDismissNotice: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppIdentity.displayName)
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundColor(MenuDesignTokens.ink)

                    if !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(MenuDesignTokens.inkSoft)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                MenuGlyphButton(systemName: "arrow.clockwise", spinning: isRefreshing) {
                    onRefresh()
                }
                .disabled(isRefreshing)
                .help(L.refreshUsage)
            }

            HStack(spacing: 8) {
                Picker("", selection: $provider) {
                    ForEach(MenuProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)

                if accountCount > 0 {
                    MenuCapsuleBadge(
                        text: L.available(availableCount, accountCount),
                        tint: availableCount > 0 ? MenuDesignTokens.positive : MenuDesignTokens.critical
                    )
                }
            }

            if let lastUpdateText {
                HStack {
                    Spacer()

                    Text(lastUpdateText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(MenuDesignTokens.inkSoft)
                }
            }

            if let notice {
                MenuNoticeRow(message: notice.message, tone: notice.tone, dismissAction: onDismissNotice)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct MenuBarEmptyState: View {
    let provider: MenuProvider
    let onAddAccount: () -> Void
    let onImportCredentials: () -> Void
    let onImportCurrentLogin: (() -> Void)?
    let onConfigureOAuth: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: provider == .codex ? "person.crop.circle.badge.plus" : "sparkles.rectangle.stack")
                    .font(.system(size: 28))
                    .foregroundColor(MenuDesignTokens.inkSoft)

                Text(L.noAccounts)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(MenuDesignTokens.ink)

                Text(provider == .codex ? L.menuCodexEmptyDescription : L.menuAntigravityEmptyDescription)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkSoft)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button {
                    onAddAccount()
                } label: {
                    Label(L.addAccount, systemImage: "plus")
                }
                .buttonStyle(MenuPrimaryButtonStyle())

                Button {
                    onImportCredentials()
                } label: {
                    Label(L.importCredentials, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(MenuSecondaryButtonStyle())
            }

            if let onImportCurrentLogin {
                HStack(spacing: 8) {
                    Button {
                        onImportCurrentLogin()
                    } label: {
                        Label(L.importAccount, systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(MenuSecondaryButtonStyle())

                    if let onConfigureOAuth {
                        Button {
                            onConfigureOAuth()
                        } label: {
                            Label(L.configureOAuth, systemImage: "key")
                        }
                        .buttonStyle(MenuSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: MenuDesignTokens.sectionRadius, style: .continuous)
                .fill(MenuDesignTokens.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MenuDesignTokens.sectionRadius, style: .continuous)
                .stroke(MenuDesignTokens.subtleBorder, lineWidth: 0.8)
        }
        .padding(.vertical, 6)
    }
}

private struct MenuBarFooter: View {
    let languageLabel: String
    let showsImportCurrentLogin: Bool
    let showsConfigureOAuth: Bool
    let onAddAccount: () -> Void
    let onConfigureOAuth: () -> Void
    let onImportCurrentLogin: () -> Void
    let onExportCredentials: () -> Void
    let onImportCredentials: () -> Void
    let onToggleLanguage: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onAddAccount()
                } label: {
                    Label(L.addAccount, systemImage: "plus")
                }
                .buttonStyle(MenuPrimaryButtonStyle())

                Button {
                    onImportCredentials()
                } label: {
                    Label(L.importCredentials, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(MenuSecondaryButtonStyle())

                Button {
                    onExportCredentials()
                } label: {
                    Label(L.exportCredentials, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(MenuSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                if showsConfigureOAuth {
                    Button {
                        onConfigureOAuth()
                    } label: {
                        Label(L.configureOAuth, systemImage: "key")
                    }
                    .buttonStyle(MenuSecondaryButtonStyle())
                }

                if showsImportCurrentLogin {
                    Button {
                        onImportCurrentLogin()
                    } label: {
                        Label(L.importAccount, systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(MenuSecondaryButtonStyle())
                }

                Spacer(minLength: 0)

                Button(languageLabel, action: onToggleLanguage)
                    .buttonStyle(MenuSecondaryButtonStyle())
                    .help("切换语言 / Switch Language")

                Button {
                    onQuit()
                } label: {
                    Label(L.quit, systemImage: "power")
                }
                .buttonStyle(MenuSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

enum AntigravityOAuthConfigWindowModel {
    static let windowID = "antigravity-oauth-config"
}

struct AntigravityOAuthConfigWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientIdInput = ""
    @State private var secretInput = ""
    @State private var cloudCodeBaseURLInput = AntigravityOAuthClient.defaultCloudCodeBaseURL
    @State private var notice: MenuHeaderNotice?

    private let store = AntigravityOAuthKeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.antigravityOAuthConfigTitle)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundColor(MenuDesignTokens.ink)

                Text(L.antigravityOAuthConfigDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice {
                MenuNoticeRow(message: notice.message, tone: notice.tone)
            }

            VStack(alignment: .leading, spacing: 12) {
                configField(
                    title: L.antigravityOAuthClientIdLabel,
                    systemImage: "person.text.rectangle",
                    content: {
                        TextField("000000000000-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com", text: $clientIdInput)
                            .textFieldStyle(.roundedBorder)
                    }
                )

                configField(
                    title: L.antigravityOAuthClientSecretLabel,
                    systemImage: "key.fill",
                    content: {
                        SecureField("client secret", text: $secretInput)
                            .textFieldStyle(.roundedBorder)
                    }
                )

                configField(
                    title: L.antigravityOAuthCloudCodeBaseURLLabel,
                    detail: L.antigravityOAuthCloudCodeBaseURLHelp,
                    systemImage: "network",
                    content: {
                        TextField(AntigravityOAuthClient.defaultCloudCodeBaseURL, text: $cloudCodeBaseURLInput)
                            .textFieldStyle(.roundedBorder)
                    }
                )
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    clearStoredConfig()
                } label: {
                    Label(L.antigravityOAuthClear, systemImage: "trash")
                }
                .buttonStyle(MenuSecondaryButtonStyle())

                Spacer(minLength: 0)

                Button(L.cancel) {
                    dismiss()
                }
                .buttonStyle(MenuSecondaryButtonStyle())

                Button {
                    saveConfig()
                } label: {
                    Label(L.antigravityOAuthSave, systemImage: "lock")
                }
                .buttonStyle(MenuPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(MenuDesignTokens.canvas)
        .onAppear(perform: loadStoredConfig)
    }

    private var canSave: Bool {
        !clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func configField<Content: View>(
        title: String,
        detail: String? = nil,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MenuDesignTokens.inkSoft)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MenuDesignTokens.ink)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MenuDesignTokens.inkSoft)
                }
            }

            content()
        }
    }

    private func loadStoredConfig() {
        do {
            guard let config = try store.load() else { return }
            clientIdInput = config.googleClientId
            secretInput = config.googleClientSecret
            cloudCodeBaseURLInput = config.cloudCodeBaseURL ?? AntigravityOAuthClient.defaultCloudCodeBaseURL
        } catch {
            notice = MenuHeaderNotice(message: error.localizedDescription, tone: .critical)
        }
    }

    private func saveConfig() {
        do {
            let baseURL = cloudCodeBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.save(
                AntigravityOAuthConfig(
                    googleClientId: clientIdInput,
                    googleClientSecret: secretInput,
                    cloudCodeBaseURL: baseURL.isEmpty ? nil : baseURL
                )
            )
            notice = MenuHeaderNotice(message: L.antigravityOAuthSaved, tone: .positive)
        } catch {
            notice = MenuHeaderNotice(message: error.localizedDescription, tone: .critical)
        }
    }

    private func clearStoredConfig() {
        do {
            try store.delete()
            clientIdInput = ""
            secretInput = ""
            cloudCodeBaseURLInput = AntigravityOAuthClient.defaultCloudCodeBaseURL
            notice = MenuHeaderNotice(message: L.antigravityOAuthCleared, tone: .positive)
        } catch {
            notice = MenuHeaderNotice(message: error.localizedDescription, tone: .critical)
        }
    }
}
