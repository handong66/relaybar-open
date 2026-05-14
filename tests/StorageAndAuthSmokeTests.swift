import Foundation

@main
struct StorageAndAuthSmokeTests {
    static func main() throws {
        try testLegacyPoolDecoding()
        try testAccountPoolRepositoryProtectsNonEmptyPool()
        try testAuthResolverFallbackAndMirrorWrites()
        try testUsageMetricSectionsSupportStructuredUsage()
        try testAccountPanelStatePrioritizesActiveHero()
        try testAccountPanelStateFallsBackToHealthyHero()
        try testTokenAccountSecondaryUsageSectionsStayCompact()
        try testAntigravityQuotaProminentDisplayModels()
        try testAntigravityExpiredTokenDoesNotBlockLocalSwitching()
        try testAntigravityAccountWithoutSwitchSnapshotCanStillBeSelectedWithRefreshToken()
        try testAntigravityOAuthInfoIncludesIdTokenAndStandardPersonalMode()
        try testAntigravityLegacyExpiredStateIsRepairedForSwitching()
        try testAntigravityCurrentLoginStateIncludesUsableAccessToken()
        try testAntigravityCurrentLoginStateCapturesSwitchSnapshot()
        try testAntigravitySwitcherRestoresCapturedSwitchSnapshot()
        try testAntigravitySwitchSnapshotDetectsMixedAccountState()
        try testAntigravityCurrentLoginStateCanImportExpiredAccessToken()
        try testProviderSummaryStateOnlyShowsActionableCopy()
        try testLanguageTogglePicksVisibleLanguageChangeFromAuto()
        try testLocalUsageReportParsing()
        try testLocalUsageParsesCodexSessionLogs()
        try testLocalUsageSourceDoesNotLaunchPackageManagers()
        try testCredentialBundleRoundTrip()
        try testCredentialBundleUsesRelayBarIdentity()
        try testCredentialBundleAcceptsLegacyCredentialType()
        try testAppIdentityUsesRelayBarBundleIdentifier()
        try testSelectiveCredentialExport()
        try testImportSelectionConflictMapping()
        try testSensitiveFileWritesUsePrivatePermissions()
        try testSensitiveExportWriteDoesNotChmodChosenParentDirectory()
        try testOAuthCallbackBindsLoopbackOnly()
        try testAntigravityOAuthConfigMissing()
        try testAntigravityOAuthConfigEnvironment()
        try testAntigravityOAuthConfigSecureStore()
        try testAntigravityOAuthConfigFile()
        try testAntigravityOAuthConfigEnvironmentOverridesFile()
        try testPublicSourceDoesNotContainBundledGoogleSecret()
        try testLegacyLanguageOverrideMigration()
        try testLocalUsageCacheDirectoryMigration()
        print("StorageAndAuthSmokeTests passed")
    }

    private static func testLegacyPoolDecoding() throws {
        let json = """
        {
          "accounts": [
            {
              "email": "legacy@example.com",
              "account_id": "acct_legacy",
              "access_token": "access",
              "refresh_token": "refresh",
              "id_token": "id"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pool = try decoder.decode(TokenPool.self, from: Data(json.utf8))

        expect(pool.accounts.count == 1, "legacy pool should decode exactly one account")
        let account = pool.accounts[0]
        expect(account.planType == "free", "legacy pool should default plan type to free")
        expect(account.primaryUsedPercent == 0, "legacy pool should default 5h usage to 0")
        expect(account.secondaryUsedPercent == 0, "legacy pool should default 7d usage to 0")
        expect(account.isActive == false, "legacy pool should default inactive")
    }

    private static func testAccountPoolRepositoryProtectsNonEmptyPool() throws {
        let tempRoot = try makeTemporaryDirectory(named: "pool-repo")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makePaths(root: tempRoot)
        let repository = AccountPoolRepository(fileManager: .default, paths: paths)

        let account = AccountBuilder.build(from: sampleTokens(accountId: "acct_pool", subject: "user_pool", email: "pool@example.com"))
        try repository.save([account])

        do {
            try repository.save([])
            throw TestFailure("repository should block accidental empty overwrite")
        } catch let error as AccountPoolRepositoryError {
            guard case .preventedEmptyOverwrite = error else {
                throw TestFailure("unexpected repository error: \(error.localizedDescription)")
            }
        }

        try repository.save([], allowEmptyOverwrite: true)
        let backupURL = tempRoot
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("token_pool.json.bak")
        expect(FileManager.default.fileExists(atPath: backupURL.path), "repository should create a backup before overwriting the pool")
    }

    private static func testAuthResolverFallbackAndMirrorWrites() throws {
        let tempRoot = try makeTemporaryDirectory(named: "auth-resolver")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makePaths(root: tempRoot)
        let resolver = CodexAuthResolver(fileManager: .default, session: .shared, paths: paths)
        let account = AccountBuilder.build(from: sampleTokens(accountId: "acct_auth", subject: "user_auth", email: "auth@example.com"))

        try resolver.writeActiveAuth(for: account)

        let configuredAuthURL = tempRoot
            .appendingPathComponent("custom-codex", isDirectory: true)
            .appendingPathComponent("auth.json")
        let defaultAuthURL = tempRoot
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")

        expect(FileManager.default.fileExists(atPath: configuredAuthURL.path), "resolver should mirror active auth into CODEX_HOME when configured")
        expect(FileManager.default.fileExists(atPath: defaultAuthURL.path), "resolver should keep writing the default ~/.codex/auth.json file")

        try Data("{invalid".utf8).write(to: configuredAuthURL, options: .atomic)

        switch resolver.loadActiveAuth() {
        case .success(let snapshot?):
            expect(snapshot.sourceURL.standardizedFileURL == defaultAuthURL.standardizedFileURL, "resolver should fall back to the default auth file when the preferred one is invalid")
            expect(snapshot.accountId == account.accountId, "resolver should read the active account id from fallback auth")
            expect(snapshot.loginIdentity == account.loginIdentity, "resolver should preserve stable login identity when reading auth")
        case .success(nil):
            throw TestFailure("resolver should find a valid fallback auth file")
        case .failure(let error):
            throw TestFailure("resolver should recover from invalid preferred auth: \(error.localizedDescription)")
        }
    }

    private static func testUsageMetricSectionsSupportStructuredUsage() throws {
        var account = AccountBuilder.build(from: sampleTokens(accountId: "acct_usage", subject: "user_usage", email: "usage@example.com"))
        account.primaryUsedPercent = 57
        account.secondaryUsedPercent = 9
        account.primaryResetAt = Date().addingTimeInterval(4 * 3600)
        account.secondaryResetAt = Date().addingTimeInterval(6 * 24 * 3600)
        account.usageSnapshot = UsageSnapshot(
            rateLimitGroups: [
                UsageRateLimitGroup(
                    primaryWindow: UsageWindowSnapshot(
                        usedPercent: 57,
                        windowDurationMinutes: 300,
                        resetAt: Date().addingTimeInterval(4 * 3600)
                    ),
                    secondaryWindow: UsageWindowSnapshot(
                        usedPercent: 9,
                        windowDurationMinutes: 7 * 1440,
                        resetAt: Date().addingTimeInterval(6 * 24 * 3600)
                    )
                ),
                UsageRateLimitGroup(
                    limitName: "gpt-5.3-codex-spark",
                    blocked: false,
                    primaryWindow: UsageWindowSnapshot(
                        usedPercent: 12,
                        windowDurationMinutes: 300,
                        resetAt: Date().addingTimeInterval(3 * 3600)
                    )
                )
            ],
            credits: UsageCreditsSnapshot(hasCredits: true, unlimited: false, balance: 1000)
        )
        account.localUsageSnapshot = LocalUsageSnapshot(
            today: LocalUsageSummary(costUSD: 47.53, totalTokens: 94_000_000),
            yesterday: LocalUsageSummary(costUSD: 30.82, totalTokens: 54_000_000),
            lastThirtyDays: LocalUsageSummary(costUSD: 87.29, totalTokens: 166_000_000)
        )

        let sections = account.usageMetricSections
        expect(sections.count == 3, "structured usage should produce usage, model, and local usage sections")
        expect(sections[0].title == L.usageTitle, "core section should use the generic usage title")
        expect(sections.contains(where: { $0.title.contains("Spark") }), "additional rate limit should surface as its own section")
        expect(sections.contains(where: { $0.title == L.usageLocalUsageTitle }), "local usage should surface as its own section")
        expect(
            sections.flatMap(\.lines).contains {
                if case .text(let text) = $0 {
                    return text.leading == L.usageTodayTitle && text.trailing?.contains("$47.53") == true
                }
                return false
            },
            "local usage section should be able to render text metrics"
        )
    }

    private static func testAccountPanelStatePrioritizesActiveHero() throws {
        var active = AccountBuilder.build(from: sampleTokens(accountId: "acct_active", subject: "user_active", email: "active@example.com"))
        active.isActive = true
        active.primaryUsedPercent = 35

        var healthy = AccountBuilder.build(from: sampleTokens(accountId: "acct_healthy", subject: "user_healthy", email: "healthy@example.com"))
        healthy.primaryUsedPercent = 5

        var warning = AccountBuilder.build(from: sampleTokens(accountId: "acct_warning", subject: "user_warning", email: "warning@example.com"))
        warning.primaryUsedPercent = 86

        var exhausted = AccountBuilder.build(from: sampleTokens(accountId: "acct_exhausted", subject: "user_exhausted", email: "exhausted@example.com"))
        exhausted.primaryUsedPercent = 100

        let state = AccountPanelState(
            accounts: [warning, active, exhausted, healthy],
            maxVisibleSecondaryAccounts: 2,
            estimatedHeroHeight: 180,
            estimatedSecondaryHeight: 84,
            listVerticalPadding: 16
        )

        expect(state.activeAccount?.storageKey == active.storageKey, "active-first layout should promote the active account to hero")
        expect(state.visibleSecondaryAccounts.count == 2, "active-first layout should cap visible secondary cards")
        expect(state.hiddenSecondaryCount == 1, "active-first layout should track overflow secondary cards")
        expect(state.availableCount == 2, "available count should still reflect all healthy accounts")
    }

    private static func testAccountPanelStateFallsBackToHealthyHero() throws {
        var warning = AccountBuilder.build(from: sampleTokens(accountId: "acct_warning_2", subject: "user_warning_2", email: "warning2@example.com"))
        warning.primaryUsedPercent = 90

        var healthy = AccountBuilder.build(from: sampleTokens(accountId: "acct_healthy_2", subject: "user_healthy_2", email: "healthy2@example.com"))
        healthy.primaryUsedPercent = 12

        var banned = AccountBuilder.build(from: sampleTokens(accountId: "acct_banned", subject: "user_banned", email: "banned@example.com"))
        banned.isSuspended = true

        let state = AccountPanelState(
            accounts: [warning, banned, healthy],
            maxVisibleSecondaryAccounts: 2,
            estimatedHeroHeight: 180,
            estimatedSecondaryHeight: 84,
            listVerticalPadding: 16
        )

        expect(state.activeAccount?.storageKey == healthy.storageKey, "without an active account, the healthiest account should become hero")
        expect(state.secondaryAccounts.count == 2, "remaining accounts should stay in the secondary list")
    }

    private static func testTokenAccountSecondaryUsageSectionsStayCompact() throws {
        var account = AccountBuilder.build(from: sampleTokens(accountId: "acct_compact", subject: "user_compact", email: "compact@example.com"))
        account.primaryUsedPercent = 57
        account.secondaryUsedPercent = 9
        account.primaryResetAt = Date().addingTimeInterval(4 * 3600)
        account.secondaryResetAt = Date().addingTimeInterval(6 * 24 * 3600)
        account.localUsageSnapshot = LocalUsageSnapshot(
            today: LocalUsageSummary(costUSD: 2.15, totalTokens: 3_750_000),
            yesterday: LocalUsageSummary(costUSD: 17.55, totalTokens: 37_300_000),
            lastThirtyDays: LocalUsageSummary(costUSD: 314.91, totalTokens: 699_000_000)
        )

        let compactSections = account.secondaryUsageMetricSections
        expect(compactSections.count == 1, "secondary card usage should stay compact and exclude the local usage ledger")
        expect(compactSections[0].id == "core", "secondary card usage should keep the core progress section")
        expect(
            compactSections[0].lines.contains {
                if case .progress(let progress) = $0 {
                    return progress.label == L.usageSessionTitle
                }
                return false
            },
            "secondary card usage should still show the session progress bar"
        )
    }

    private static func testAntigravityQuotaProminentDisplayModels() throws {
        let quota = AntigravityQuotaData(
            models: [
                AntigravityModelQuota(
                    name: "gemini-3-flash",
                    remainingPercent: 100,
                    resetTime: "2026-04-22T17:37:54Z",
                    displayName: "Gemini 3 Flash"
                ),
                AntigravityModelQuota(
                    name: "gemini-3-flash-thinking",
                    remainingPercent: 85,
                    resetTime: "2026-04-22T17:37:54Z",
                    displayName: "Gemini 3 Flash"
                ),
                AntigravityModelQuota(
                    name: "claude-sonnet-4-6",
                    remainingPercent: 12,
                    resetTime: "2026-04-22T17:37:54Z",
                    displayName: "Claude Sonnet 4.6 (Thinking)"
                ),
                AntigravityModelQuota(
                    name: "gpt-5-high",
                    remainingPercent: 25,
                    resetTime: "2026-04-22T17:37:54Z",
                    displayName: "GPT-5 High"
                ),
                AntigravityModelQuota(
                    name: "gemini-3-pro",
                    remainingPercent: 48,
                    resetTime: "2026-04-22T17:37:54Z",
                    displayName: "Gemini 3 Pro"
                )
            ],
            subscriptionTier: "PRO"
        )

        let prominent = quota.prominentDisplayModels(limit: 3)
        let overflow = quota.overflowDisplayModels(limit: 3)
        let combined = prominent + overflow

        expect(prominent.count == 3, "hero Antigravity view should limit the number of prominent models")
        expect(overflow.count == 1, "overflow models should be split out from the prominent set")
        expect(prominent.first?.displayTitle.contains("Claude") == true, "lowest remaining quota should be prioritized first")
        expect(
            combined.first(where: { $0.displayTitle == "Gemini 3 Flash" })?.remainingPercent == 85,
            "duplicate display names should keep the most relevant remaining quota entry"
        )
    }

    private static func testAntigravityExpiredTokenDoesNotBlockLocalSwitching() throws {
        var account = sampleAntigravityAccount(id: "ag_switchable_expired", email: "switchable@example.com", tier: "PRO")
        account.tokenExpired = true

        expect(account.canSwitchLocally, "Antigravity accounts with a captured local login snapshot should remain locally switchable")
        expect(account.isAvailable, "Antigravity availability should reflect local switchability, not RelayBar OAuth refreshability")
    }

    private static func testAntigravityAccountWithoutSwitchSnapshotCanStillBeSelectedWithRefreshToken() throws {
        var account = sampleAntigravityAccount(id: "ag_missing_snapshot", email: "missing-snapshot@example.com", tier: "PRO")
        account.localStateSnapshot = nil

        expect(account.canSwitchLocally, "refresh-token Antigravity accounts should remain selectable for fresh-token restore or user-provided OAuth refresh")
        expect(account.isAvailable, "Antigravity availability should count selectable refresh-token accounts without requiring bundled OAuth credentials")
    }

    private static func testAntigravityOAuthInfoIncludesIdTokenAndStandardPersonalMode() throws {
        let oauthPayload = AntigravityProtobuf.createOAuthInfo(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiryTimestamp: Date(timeIntervalSince1970: 1234),
            isGcpTos: true,
            idToken: "id-token",
            email: "person@gmail.com"
        )

        let idToken = try AntigravityProtobuf.findField(oauthPayload, fieldNumber: 5)
            .flatMap { String(data: $0, encoding: .utf8) }
        let isGcpTos = try AntigravityProtobuf.findVarintField(oauthPayload, fieldNumber: 6)

        expect(idToken == "id-token", "Antigravity OAuth payload should preserve id_token when available")
        expect(isGcpTos == nil, "personal Google accounts should use standard Antigravity mode, matching Antigravity-Manager")
    }

    private static func testAntigravityLegacyExpiredStateIsRepairedForSwitching() throws {
        var account = sampleAntigravityAccount(id: "ag_repair_expired", email: "repair@example.com", tier: "PRO")
        account.tokenExpired = true
        account.lastChecked = Date(timeIntervalSince1970: 1234)
        let originalQuota = account.quota

        let repair = AntigravityAccountStore.repairLocalSwitchState(in: [account])

        expect(repair.changed, "legacy Antigravity tokenExpired state should be repaired for locally switchable accounts")
        expect(repair.accounts.count == 1, "repair should preserve account count")
        expect(repair.accounts[0].tokenExpired == false, "repair should clear tokenExpired for locally switchable accounts")
        expect(repair.accounts[0].lastChecked == account.lastChecked, "repair should preserve lastChecked")
        expect(repair.accounts[0].quota == originalQuota, "repair should preserve quota data")
    }

    private static func testAntigravityCurrentLoginStateIncludesUsableAccessToken() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-current-login-state")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makeAntigravityPaths(root: tempRoot)
        try FileManager.default.createDirectory(
            at: paths.stateDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let db = try AntigravitySQLiteDatabase(url: paths.stateDatabaseURL)
        try db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);")

        let expiry = Date().addingTimeInterval(3600)
        let oauthPayload = AntigravityProtobuf.createOAuthInfo(
            accessToken: "current-access-token",
            refreshToken: "current-refresh-token",
            expiryTimestamp: expiry,
            isGcpTos: true
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: [
                "antigravityUnifiedStateSync.oauthToken",
                AntigravityProtobuf.createUnifiedStateEntry(
                    sentinelKey: "oauthTokenInfoSentinelKey",
                    payload: oauthPayload
                )
            ]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: [
                "antigravityUnifiedStateSync.userStatus",
                AntigravityProtobuf.createUnifiedStateEntry(
                    sentinelKey: "userStatusSentinelKey",
                    payload: AntigravityProtobuf.createUserStatusPayload(email: "current-ag@example.com")
                )
            ]
        )

        let state = try AntigravityAccountImporter.extractCurrentLoginState(from: paths.stateDatabaseURL)
        expect(state.accessToken == "current-access-token", "current login import should preserve the live access token")
        expect(state.refreshToken == "current-refresh-token", "current login import should preserve the refresh token")
        expect(state.email == "current-ag@example.com", "current login import should read the local Antigravity user email")
        expect(abs(state.expiryTimestamp.timeIntervalSince1970 - expiry.timeIntervalSince1970) < 1, "current login import should preserve token expiry")
        expect(state.canImportWithoutRefresh(now: Date()), "fresh local login state should be importable without OAuth refresh")
    }

    private static func testAntigravityCurrentLoginStateCapturesSwitchSnapshot() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-current-login-snapshot")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makeAntigravityPaths(root: tempRoot)
        try FileManager.default.createDirectory(
            at: paths.stateDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let db = try AntigravitySQLiteDatabase(url: paths.stateDatabaseURL)
        try db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);")

        let oauthPayload = AntigravityProtobuf.createOAuthInfo(
            accessToken: "snapshot-access-token",
            refreshToken: "snapshot-refresh-token",
            expiryTimestamp: Date().addingTimeInterval(3600),
            isGcpTos: false
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: [
                "antigravityUnifiedStateSync.oauthToken",
                AntigravityProtobuf.createUnifiedStateEntry(
                    sentinelKey: "oauthTokenInfoSentinelKey",
                    payload: oauthPayload
                )
            ]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: [
                "antigravityUnifiedStateSync.userStatus",
                AntigravityProtobuf.createUnifiedStateEntry(
                    sentinelKey: "userStatusSentinelKey",
                    payload: AntigravityProtobuf.createUserStatusPayload(email: "snapshot@example.com")
                )
            ]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityAuthStatus", "raw-auth-status-for-snapshot"]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["jetskiStateSync.agentManagerInitState", "raw-legacy-state-for-snapshot"]
        )

        let state = try AntigravityAccountImporter.extractCurrentLoginState(from: paths.stateDatabaseURL)
        let snapshot = try state.localStateSnapshot.required("current login should include a local switch snapshot")

        expect(snapshot.stateItems["antigravityUnifiedStateSync.oauthToken"] != nil, "snapshot should preserve the raw OAuth row")
        expect(snapshot.stateItems["antigravityUnifiedStateSync.userStatus"] != nil, "snapshot should preserve the raw user status row")
        expect(snapshot.stateItems["antigravityAuthStatus"] == "raw-auth-status-for-snapshot", "snapshot should preserve auth status instead of reconstructing it")
        expect(snapshot.stateItems["jetskiStateSync.agentManagerInitState"] == "raw-legacy-state-for-snapshot", "snapshot should preserve legacy init state when present")
        expect(snapshot.missingStateKeys.contains("antigravityUnifiedStateSync.enterprisePreferences"), "snapshot should remember absent optional state rows so stale rows can be cleared on restore")
    }

    private static func testAntigravitySwitcherRestoresCapturedSwitchSnapshot() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-switch-snapshot")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makeAntigravityPaths(root: tempRoot)
        try FileManager.default.createDirectory(
            at: paths.stateDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let db = try AntigravitySQLiteDatabase(url: paths.stateDatabaseURL)
        try db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);")
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityUnifiedStateSync.oauthToken", "stale-oauth-row"]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityUnifiedStateSync.enterprisePreferences", "stale-project-row"]
        )

        let snapshot = AntigravityLocalStateSnapshot(
            stateItems: [
                "antigravityUnifiedStateSync.oauthToken": "snapshot-oauth-row",
                "antigravityUnifiedStateSync.userStatus": "snapshot-user-row",
                "antigravityAuthStatus": "snapshot-auth-status-row",
                "jetskiStateSync.agentManagerInitState": "snapshot-legacy-row"
            ],
            missingStateKeys: ["antigravityUnifiedStateSync.enterprisePreferences"],
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        try AntigravitySwitcher.restoreLocalStateSnapshot(snapshot, toDatabase: paths.stateDatabaseURL)

        let restoredOAuth = try db.queryString("SELECT value FROM ItemTable WHERE key = ?", bindings: ["antigravityUnifiedStateSync.oauthToken"])
        let restoredUserStatus = try db.queryString("SELECT value FROM ItemTable WHERE key = ?", bindings: ["antigravityUnifiedStateSync.userStatus"])
        let restoredAuthStatus = try db.queryString("SELECT value FROM ItemTable WHERE key = ?", bindings: ["antigravityAuthStatus"])
        let restoredLegacy = try db.queryString("SELECT value FROM ItemTable WHERE key = ?", bindings: ["jetskiStateSync.agentManagerInitState"])
        let restoredEnterprise = try db.queryString("SELECT value FROM ItemTable WHERE key = ?", bindings: ["antigravityUnifiedStateSync.enterprisePreferences"])

        expect(
            restoredOAuth == "snapshot-oauth-row",
            "switching should restore the captured OAuth row verbatim"
        )
        expect(
            restoredUserStatus == "snapshot-user-row",
            "switching should restore the captured user status row verbatim"
        )
        expect(
            restoredAuthStatus == "snapshot-auth-status-row",
            "switching should restore the captured auth status row verbatim"
        )
        expect(
            restoredLegacy == "snapshot-legacy-row",
            "switching should restore the captured legacy row verbatim"
        )
        expect(
            restoredEnterprise == nil,
            "switching should clear stale optional rows that were absent when the account was captured"
        )
    }

    private static func testAntigravitySwitchSnapshotDetectsMixedAccountState() throws {
        let snapshot = AntigravityLocalStateSnapshot(
            stateItems: [
                "antigravityUnifiedStateSync.oauthToken": "oauth-row",
                "antigravityUnifiedStateSync.userStatus": "encoded-user-row",
                "antigravityAuthStatus": "signed in as other@example.com"
            ],
            missingStateKeys: [],
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        expect(
            !snapshot.hasConsistentAuthenticationEmail("target@example.com"),
            "snapshot should reject mixed Antigravity auth rows from another account"
        )
        expect(
            snapshot.hasConsistentAuthenticationEmail("other@example.com"),
            "snapshot should accept auth rows that mention the same account"
        )
    }

    private static func testAntigravityCurrentLoginStateCanImportExpiredAccessToken() throws {
        let state = ImportedAntigravityOAuthState(
            accessToken: "expired-access-token",
            refreshToken: "current-refresh-token",
            expiryTimestamp: Date().addingTimeInterval(-3600),
            tokenType: "Bearer",
            email: "expired-current@example.com",
            isGcpTos: true,
            projectId: "project-current"
        )

        expect(!state.canImportWithoutRefresh(now: Date()), "expired access token should not be treated as fresh")
        expect(state.canImportFromLocalState(), "expired current login should still be importable when refresh token and email are present")
    }

    private static func testProviderSummaryStateOnlyShowsActionableCopy() throws {
        expect(
            ProviderSummaryState.subtitle(
                provider: .codex,
                accountCount: 2,
                isRefreshing: false
            ) == nil,
            "normal populated state should not show explanatory header copy"
        )

        expect(
            ProviderSummaryState.subtitle(
                provider: .antigravity,
                accountCount: 0,
                isRefreshing: false
            ) == L.menuAntigravityEmptyDescription,
            "empty provider state should still explain the next useful action"
        )

        expect(
            ProviderSummaryState.subtitle(
                provider: .codex,
                accountCount: 3,
                isRefreshing: true
            ) == L.menuRefreshingNow,
            "refreshing state should still surface live status copy"
        )
    }

    private static func testLanguageTogglePicksVisibleLanguageChangeFromAuto() throws {
        expect(
            L.nextLanguageOverride(currentOverride: nil, resolvedZh: true) == false,
            "on a Chinese system, the first click should switch to explicit English"
        )
        expect(
            L.nextLanguageOverride(currentOverride: nil, resolvedZh: false) == true,
            "on a non-Chinese system, the first click should switch to explicit Chinese"
        )
        expect(
            L.nextLanguageOverride(currentOverride: true, resolvedZh: true) == false,
            "clicking from explicit Chinese should switch to explicit English"
        )
        expect(
            L.nextLanguageOverride(currentOverride: false, resolvedZh: false) == true,
            "clicking from explicit English should switch to explicit Chinese"
        )
    }

    private static func testLocalUsageReportParsing() throws {
        let json = """
        {
          "daily": [
            {
              "date": "Apr 13, 2026",
              "totalTokens": 54000000,
              "costUSD": 30.82
            },
            {
              "date": "Apr 14, 2026",
              "totalTokens": 94000000,
              "costUSD": 47.53
            }
          ]
        }
        """

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        let now = formatter.date(from: "2026-04-14T12:00:00+08:00")!

        let snapshot = CodexLocalUsageService.parseDailyReportData(
            Data(json.utf8),
            now: now,
            timeZone: TimeZone(identifier: "Asia/Hong_Kong")!
        )

        expect(snapshot != nil, "local usage parser should decode ccusage daily JSON")
        expect(snapshot?.today.costUSD == 47.53, "today summary should match the current day row")
        expect(snapshot?.today.totalTokens == 94_000_000, "today token count should match the current day row")
        expect(snapshot?.yesterday.costUSD == 30.82, "yesterday summary should match the previous day row")
        expect(snapshot?.lastThirtyDays?.totalTokens == 148_000_000, "30 day summary should aggregate recent rows")
    }

    private static func testLocalUsageParsesCodexSessionLogs() throws {
        let tempRoot = try makeTemporaryDirectory(named: "codex-session-usage")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let codexHomeURL = tempRoot.appendingPathComponent(".codex", isDirectory: true)
        let sessionsURL = codexHomeURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026/05/07", isDirectory: true)
        let archivedURL = codexHomeURL.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedURL, withIntermediateDirectories: true)

        let lines = [
            tokenCountLine(timestamp: "2026-05-07T08:00:00Z", totalTokens: 100),
            tokenCountLine(timestamp: "2026-05-07T10:00:00Z", totalTokens: 200),
            tokenCountLine(timestamp: "2026-05-06T23:30:00Z", totalTokens: 300),
            tokenCountLine(timestamp: "2026-04-20T12:00:00Z", totalTokens: 400),
            tokenCountLine(timestamp: "2026-03-20T12:00:00Z", totalTokens: 999)
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: sessionsURL.appendingPathComponent("session.jsonl"))
        try Data(tokenCountLine(timestamp: "2026-05-07T12:00:00Z", totalTokens: 50).utf8)
            .write(to: archivedURL.appendingPathComponent("archived.jsonl"))

        let now = ISO8601DateFormatter().date(from: "2026-05-07T14:00:00Z")!
        let snapshot = CodexLocalUsageService.parseSessionLogUsage(
            codexHomeURL: codexHomeURL,
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        expect(snapshot != nil, "local usage parser should read Codex session JSONL token_count events")
        expect(snapshot?.today.totalTokens == 350, "today should aggregate only today's incremental token usage")
        expect(snapshot?.yesterday.totalTokens == 300, "yesterday should aggregate previous-day incremental token usage")
        expect(snapshot?.lastThirtyDays?.totalTokens == 1_050, "30 day summary should exclude events older than 30 days")
        expect(snapshot?.today.costUSD == 0, "local Codex logs do not expose cost and should not invent one")
    }

    private static func testLocalUsageSourceDoesNotLaunchPackageManagers() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("RelayBar/Services/CodexLocalUsageService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["@ccusage/codex@latest", "Process()", "npx", "bunx", "process.environment"] {
            expect(!source.contains(forbidden), "local usage service should not invoke package managers or child processes: \(forbidden)")
        }
    }

    private static func testCredentialBundleRoundTrip() throws {
        var codexAccount = AccountBuilder.build(from: sampleTokens(accountId: "acct_export", subject: "user_export", email: "export@example.com"))
        codexAccount.isActive = true
        codexAccount.primaryUsedPercent = 42

        let antigravityAccount = AntigravityAccount(
            email: "ag@example.com",
            name: "AG User",
            token: AntigravityTokenData(
                accessToken: "ag-access",
                refreshToken: "ag-refresh",
                expiresIn: 3600,
                email: "ag@example.com",
                projectId: "project-123"
            ),
            deviceProfile: AntigravityDeviceProfile(
                machineId: "auth0|user_123",
                macMachineId: "mac-123",
                devDeviceId: "dev-123",
                sqmId: "{SQM-123}"
            ),
            quota: AntigravityQuotaData(
                models: [
                    AntigravityModelQuota(
                        name: "claude-sonnet-4-6",
                        remainingPercent: 40,
                        resetTime: "2026-04-22T17:37:54Z",
                        displayName: "Claude Sonnet 4.6 (Thinking)"
                    )
                ]
            ),
            isActive: true
        )

        let antigravityPool = AntigravityAccountPool(
            currentAccountId: antigravityAccount.id,
            accounts: [antigravityAccount]
        )

        let service = CredentialTransferService.shared
        let exported = try service.exportBundleData(
            codexAccounts: [codexAccount],
            activeCodexStorageKey: codexAccount.storageKey,
            antigravityPool: antigravityPool
        )
        let imported = try service.importBundleData(exported)

        expect(imported.codexAccounts.count == 1, "bundle should preserve Codex accounts")
        expect(imported.activeCodexStorageKey == codexAccount.storageKey, "bundle should preserve active Codex account")
        expect(imported.antigravityPool.accounts.count == 1, "bundle should preserve Antigravity accounts")
        expect(imported.antigravityPool.currentAccountId == antigravityAccount.id, "bundle should preserve active Antigravity account")
        expect(imported.antigravityPool.accounts[0].quota?.models.first?.displayName == "Claude Sonnet 4.6 (Thinking)", "bundle should preserve Antigravity quota data")
    }

    private static func testCredentialBundleUsesRelayBarIdentity() throws {
        let service = CredentialTransferService.shared
        let exported = try service.exportBundleData(
            codexAccounts: [],
            activeCodexStorageKey: nil,
            antigravityPool: AntigravityAccountPool(currentAccountId: nil, accounts: [
                sampleAntigravityAccount(id: "ag_bundle", email: "ag-bundle@example.com", tier: "PRO")
            ])
        )
        let json = try JSONSerialization.jsonObject(with: exported) as? [String: Any]
        let filename = service.suggestedFilename(now: Date(timeIntervalSince1970: 0))

        expect(json?["type"] as? String == "relaybar.credentials", "new exports should use RelayBar credential bundle type")
        expect(filename.hasPrefix("RelayBar-Credentials-"), "export filename should use RelayBar prefix")
        expect(filename.hasSuffix(".json"), "export filename should remain JSON")
        expect(!filename.contains("Codex"), "export filename should not use the legacy product name")
    }

    private static func testCredentialBundleAcceptsLegacyCredentialType() throws {
        let account = AccountBuilder.build(
            from: sampleTokens(
                accountId: "acct_legacy_bundle",
                subject: "user_legacy_bundle",
                email: "legacy-bundle@example.com"
            )
        )
        let bundle = CredentialTransferBundle(
            type: AppIdentity.legacyCredentialBundleTypes.first ?? "missing-legacy-type",
            codexAccounts: [account],
            activeCodexStorageKey: account.storageKey,
            antigravityPool: AntigravityAccountPool(currentAccountId: nil, accounts: [])
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let imported = try CredentialTransferService.shared.importBundleData(data)

        expect(AppIdentity.legacyCredentialBundleTypes.contains(imported.type), "legacy credential bundle type should remain readable")
        expect(imported.codexAccounts.count == 1, "legacy credential bundle should preserve Codex accounts")
    }

    private static func testAppIdentityUsesRelayBarBundleIdentifier() throws {
        expect(AppIdentity.bundleIdentifier == "com.handong66.relaybar", "RelayBar should use its current bundle identifier")
        expect(!AppIdentity.bundleIdentifier.contains("xmasdong"), "current RelayBar bundle identifier should not contain the old xmasdong prefix")
        expect(AppIdentity.legacyBundleIdentifiers.contains("xmasdong.relaybar"), "old RelayBar defaults domain should stay available for migration only")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let packageScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package_app.sh"),
            encoding: .utf8
        )
        let xcodeProject = try String(
            contentsOf: root.appendingPathComponent("RelayBar.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        expect(packageScript.contains("<string>\(AppIdentity.bundleIdentifier)</string>"), "packaged app should use the current RelayBar bundle identifier")
        expect(!packageScript.contains("<string>xmasdong.relaybar</string>"), "package script should not create xmasdong.relaybar apps")
        expect(xcodeProject.contains("PRODUCT_BUNDLE_IDENTIFIER = \(AppIdentity.bundleIdentifier);"), "Xcode builds should use the current RelayBar bundle identifier")
        expect(!xcodeProject.contains("PRODUCT_BUNDLE_IDENTIFIER = xmasdong.relaybar;"), "Xcode project should not create xmasdong.relaybar apps")
    }

    private static func testSelectiveCredentialExport() throws {
        let codexA = AccountBuilder.build(from: sampleTokens(accountId: "acct_a", subject: "user_a", email: "a@example.com"))
        var codexB = AccountBuilder.build(from: sampleTokens(accountId: "acct_b", subject: "user_b", email: "b@example.com"))
        codexB.isActive = true

        let antigravityA = sampleAntigravityAccount(
            id: "ag_a",
            email: "ag-a@example.com",
            tier: "PLUS",
            isActive: false
        )
        let antigravityB = sampleAntigravityAccount(
            id: "ag_b",
            email: "ag-b@example.com",
            tier: "PRO",
            isActive: true
        )

        let service = CredentialTransferService.shared
        let items = service.exportItems(
            codexAccounts: [codexA, codexB],
            activeCodexStorageKey: codexB.storageKey,
            antigravityPool: AntigravityAccountPool(
                currentAccountId: antigravityB.id,
                accounts: [antigravityA, antigravityB]
            )
        )

        let selectedIDs = Set(
            items
                .filter { $0.codexAccount?.storageKey == codexA.storageKey || $0.antigravityAccount?.id == antigravityB.id }
                .map(\.id)
        )
        let selection = service.makeSelectionResult(
            from: items,
            selectedItemIDs: selectedIDs,
            conflictActions: [:]
        )
        let exported = try service.exportBundleData(from: selection)
        let imported = try service.importBundleData(exported)

        expect(imported.codexAccounts.count == 1, "selective export should keep only selected Codex accounts")
        expect(imported.codexAccounts[0].storageKey == codexA.storageKey, "selective export should preserve the selected Codex account")
        expect(imported.activeCodexStorageKey == nil, "active Codex key should be omitted when the active account is not selected")
        expect(imported.antigravityPool.accounts.count == 1, "selective export should keep only selected Antigravity accounts")
        expect(imported.antigravityPool.accounts[0].id == antigravityB.id, "selective export should preserve the selected Antigravity account")
        expect(imported.antigravityPool.currentAccountId == antigravityB.id, "selected active Antigravity account should remain marked active in the bundle")
    }

    private static func testImportSelectionConflictMapping() throws {
        let existingCodex = AccountBuilder.build(from: sampleTokens(accountId: "acct_existing", subject: "user_existing", email: "existing@example.com"))
        let incomingCodexDuplicate = existingCodex
        let incomingCodexNew = AccountBuilder.build(from: sampleTokens(accountId: "acct_new", subject: "user_new", email: "new@example.com"))

        let existingAntigravity = sampleAntigravityAccount(
            id: "local-ag",
            email: "shared@example.com",
            tier: "PLUS"
        )
        let incomingAntigravityDuplicate = sampleAntigravityAccount(
            id: "bundle-ag-dup",
            email: "shared@example.com",
            tier: "PRO"
        )
        let incomingAntigravityNew = sampleAntigravityAccount(
            id: "bundle-ag-new",
            email: "fresh@example.com",
            tier: "PRO"
        )

        let bundle = CredentialTransferBundle(
            codexAccounts: [incomingCodexDuplicate, incomingCodexNew],
            activeCodexStorageKey: incomingCodexDuplicate.storageKey,
            antigravityPool: AntigravityAccountPool(
                currentAccountId: incomingAntigravityDuplicate.id,
                accounts: [incomingAntigravityDuplicate, incomingAntigravityNew]
            )
        )

        let service = CredentialTransferService.shared
        let items = service.importItems(
            from: bundle,
            existingCodexAccounts: [existingCodex],
            existingAntigravityAccounts: [existingAntigravity]
        )

        let codexDuplicateItem = try requiredItem(
            in: items,
            where: { $0.codexAccount?.storageKey == incomingCodexDuplicate.storageKey }
        )
        let codexNewItem = try requiredItem(
            in: items,
            where: { $0.codexAccount?.storageKey == incomingCodexNew.storageKey }
        )
        let antigravityDuplicateItem = try requiredItem(
            in: items,
            where: { $0.antigravityAccount?.id == incomingAntigravityDuplicate.id }
        )

        expect(codexDuplicateItem.hasConflict, "existing Codex account should be marked as duplicate")
        expect(!codexNewItem.hasConflict, "new Codex account should not be marked as duplicate")
        expect(antigravityDuplicateItem.hasConflict, "Antigravity email collision should be marked as duplicate")

        let selectedIDs = Set([codexNewItem.id, antigravityDuplicateItem.id])
        let selection = service.makeSelectionResult(
            from: items,
            selectedItemIDs: selectedIDs,
            conflictActions: [antigravityDuplicateItem.id: .keepLocal]
        )

        expect(selection.codexAccounts.count == 1, "selection result should keep only selected Codex accounts")
        expect(selection.codexAccounts[0].storageKey == incomingCodexNew.storageKey, "selection result should preserve the selected new Codex account")
        expect(selection.antigravityPool.accounts.count == 1, "selection result should keep only selected Antigravity accounts")
        expect(selection.antigravityPool.accounts[0].id == incomingAntigravityDuplicate.id, "selection result should preserve the selected Antigravity account")
        expect(selection.antigravityConflictActions[incomingAntigravityDuplicate.id] == .keepLocal, "selection result should preserve per-account conflict actions")
    }

    private static func testSensitiveFileWritesUsePrivatePermissions() throws {
        let tempRoot = try makeTemporaryDirectory(named: "private-permissions")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = makePaths(root: tempRoot)
        let account = AccountBuilder.build(from: sampleTokens(accountId: "acct_perm", subject: "user_perm", email: "perm@example.com"))
        let updatedAccount = AccountBuilder.build(from: sampleTokens(accountId: "acct_perm_2", subject: "user_perm_2", email: "perm2@example.com"))

        let repository = AccountPoolRepository(fileManager: .default, paths: paths)
        try repository.save([account])
        try repository.save([account, updatedAccount])

        let codexDirectory = tempRoot.appendingPathComponent(".codex", isDirectory: true)
        let poolURL = codexDirectory.appendingPathComponent("token_pool.json")
        let poolBackupURL = codexDirectory.appendingPathComponent("token_pool.json.bak")

        let codexDirectoryPermissions = try posixPermissions(codexDirectory)
        let poolPermissions = try posixPermissions(poolURL)
        let poolBackupPermissions = try posixPermissions(poolBackupURL)
        expect(codexDirectoryPermissions == 0o700, "credential directory should be private")
        expect(poolPermissions == 0o600, "Codex token pool should be readable only by the owner")
        expect(poolBackupPermissions == 0o600, "Codex token pool backup should be readable only by the owner")

        let resolver = CodexAuthResolver(fileManager: .default, session: .shared, paths: paths)
        try resolver.writeActiveAuth(for: account)
        try resolver.writeActiveAuth(for: updatedAccount)

        let defaultAuthURL = codexDirectory.appendingPathComponent("auth.json")
        let defaultAuthBackupURL = codexDirectory.appendingPathComponent("auth.json.bak")
        let configuredAuthURL = tempRoot
            .appendingPathComponent("custom-codex", isDirectory: true)
            .appendingPathComponent("auth.json")

        let defaultAuthPermissions = try posixPermissions(defaultAuthURL)
        let defaultAuthBackupPermissions = try posixPermissions(defaultAuthBackupURL)
        let configuredAuthPermissions = try posixPermissions(configuredAuthURL)
        expect(defaultAuthPermissions == 0o600, "Codex auth file should be readable only by the owner")
        expect(defaultAuthBackupPermissions == 0o600, "Codex auth backup should be readable only by the owner")
        expect(configuredAuthPermissions == 0o600, "configured Codex auth mirror should be readable only by the owner")

        let antigravityPaths = makeAntigravityPaths(root: tempRoot)
        let antigravityAccount = sampleAntigravityAccount(id: "ag_perm", email: "ag-perm@example.com", tier: "PRO")
        let antigravityUpdatedAccount = sampleAntigravityAccount(id: "ag_perm_2", email: "ag-perm2@example.com", tier: "PRO")
        let antigravityRepository = AntigravityAccountRepository(fileManager: .default, paths: antigravityPaths)
        try antigravityRepository.save(AntigravityAccountPool(currentAccountId: antigravityAccount.id, accounts: [antigravityAccount]))
        try antigravityRepository.save(AntigravityAccountPool(currentAccountId: antigravityUpdatedAccount.id, accounts: [antigravityAccount, antigravityUpdatedAccount]))

        let antigravityPoolURL = codexDirectory.appendingPathComponent("antigravity_pool.json")
        let antigravityBackupURL = codexDirectory.appendingPathComponent("antigravity_pool.json.bak")
        let antigravityPoolPermissions = try posixPermissions(antigravityPoolURL)
        let antigravityBackupPermissions = try posixPermissions(antigravityBackupURL)
        expect(antigravityPoolPermissions == 0o600, "Antigravity token pool should be readable only by the owner")
        expect(antigravityBackupPermissions == 0o600, "Antigravity token pool backup should be readable only by the owner")
    }

    private static func testSensitiveExportWriteDoesNotChmodChosenParentDirectory() throws {
        let tempRoot = try makeTemporaryDirectory(named: "export-permissions")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let exportDirectory = tempRoot.appendingPathComponent("chosen-export-folder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        let exportURL = exportDirectory.appendingPathComponent("RelayBar-Credentials-test.json")
        try SecureFileWriter.writeSensitiveData(
            Data("{\"type\":\"relaybar.credentials\"}".utf8),
            to: exportURL,
            secureParentDirectory: false
        )

        let exportDirectoryPermissions = try posixPermissions(exportDirectory)
        let exportFilePermissions = try posixPermissions(exportURL)
        expect(exportDirectoryPermissions == 0o755, "export should not chmod a user-selected parent directory")
        expect(exportFilePermissions == 0o600, "exported credential bundle should be readable only by the owner")
    }

    private static func testOAuthCallbackBindsLoopbackOnly() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("RelayBar/Services/OAuthManager.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        expect(!source.contains("INADDR_ANY"), "OAuth callback server must not bind to all interfaces")
        expect(source.contains("127.0.0.1"), "OAuth callback server should bind explicitly to loopback")
    }

    private static func testAntigravityOAuthConfigMissing() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-oauth-missing")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let resolver = AntigravityOAuthConfigResolver(
            environment: { [:] },
            secureStore: nil,
            configURL: tempRoot.appendingPathComponent("missing.json")
        )

        do {
            _ = try resolver.load()
            throw TestFailure("missing Antigravity OAuth config should fail")
        } catch let error as AntigravityOAuthError {
            guard case .missingOAuthConfiguration = error else {
                throw TestFailure("unexpected missing-config error: \(error.localizedDescription)")
            }
        }
    }

    private static func testAntigravityOAuthConfigEnvironment() throws {
        let resolver = AntigravityOAuthConfigResolver(environment: {
            [
                AntigravityOAuthConfigResolver.clientIdEnvironmentKey: "env-client.apps.googleusercontent.com",
                AntigravityOAuthConfigResolver.googleSecretEnvironmentKey: "env-secret",
                AntigravityOAuthConfigResolver.cloudCodeBaseURLEnvironmentKey: "https://env.example.test"
            ]
        })

        let config = try resolver.load()
        expect(config.googleClientId == "env-client.apps.googleusercontent.com", "resolver should read client id from environment")
        expect(config.googleClientSecret == "env-secret", "resolver should read client secret from environment")
        expect(config.cloudCodeBaseURL == "https://env.example.test", "resolver should read cloud code base URL from environment")
    }

    private static func testAntigravityOAuthConfigSecureStore() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-oauth-secure-store")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = InMemoryAntigravityOAuthConfigStore()
        try store.save(
            AntigravityOAuthConfig(
                googleClientId: "stored-client.apps.googleusercontent.com",
                googleClientSecret: "stored-secret",
                cloudCodeBaseURL: "https://stored.example.test"
            )
        )

        let resolver = AntigravityOAuthConfigResolver(
            environment: { [:] },
            secureStore: store,
            configURL: tempRoot.appendingPathComponent("missing.json")
        )

        let config = try resolver.load()
        expect(config.googleClientId == "stored-client.apps.googleusercontent.com", "resolver should read client id from secure store")
        expect(config.googleClientSecret == "stored-secret", "resolver should read client secret from secure store")
        expect(config.cloudCodeBaseURL == "https://stored.example.test", "resolver should read cloud code base URL from secure store")
    }

    private static func testAntigravityOAuthConfigFile() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-oauth-file")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let configURL = tempRoot.appendingPathComponent("antigravity-oauth.json")
        let json = """
        {
          "google_client_id": "file-client.apps.googleusercontent.com",
          "google_client_secret": "file-secret",
          "cloud_code_base_url": "https://file.example.test"
        }
        """
        try Data(json.utf8).write(to: configURL)

        let resolver = AntigravityOAuthConfigResolver(
            environment: { [:] },
            configURL: configURL
        )

        let config = try resolver.load()
        expect(config.googleClientId == "file-client.apps.googleusercontent.com", "resolver should read client id from config file")
        expect(config.googleClientSecret == "file-secret", "resolver should read client secret from config file")
        expect(config.cloudCodeBaseURL == "https://file.example.test", "resolver should read cloud code base URL from config file")
    }

    private static func testAntigravityOAuthConfigEnvironmentOverridesFile() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ag-oauth-precedence")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let configURL = tempRoot.appendingPathComponent("antigravity-oauth.json")
        let json = """
        {
          "google_client_id": "file-client.apps.googleusercontent.com",
          "google_client_secret": "file-secret"
        }
        """
        try Data(json.utf8).write(to: configURL)

        let resolver = AntigravityOAuthConfigResolver(
            environment: {
                [
                    AntigravityOAuthConfigResolver.clientIdEnvironmentKey: "env-client.apps.googleusercontent.com",
                    AntigravityOAuthConfigResolver.googleSecretEnvironmentKey: "env-secret"
                ]
            },
            configURL: configURL
        )

        let config = try resolver.load()
        expect(config.googleClientId == "env-client.apps.googleusercontent.com", "environment client id should override file config")
        expect(config.googleClientSecret == "env-secret", "environment client secret should override file config")
    }

    private static func testPublicSourceDoesNotContainBundledGoogleSecret() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("RelayBar/Services/AntigravityOAuthConfig.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let googleSecretPrefix = "GOC" + "SPX"
        expect(!source.contains(googleSecretPrefix), "public source should not contain a Google OAuth client secret prefix")
        expect(!source.contains("builtInClientSecret"), "public source should not define a bundled Antigravity OAuth client secret")
        expect(!source.contains("builtInClientId"), "public source should not define a bundled Antigravity OAuth client id")
    }

    private static func testLegacyLanguageOverrideMigration() throws {
        let suiteName = "relaybar-tests-\(UUID().uuidString)"
        let legacySuiteName = "relaybar-legacy-tests-\(UUID().uuidString)"
        guard let newDefaults = UserDefaults(suiteName: suiteName),
              let legacyDefaults = UserDefaults(suiteName: legacySuiteName) else {
            throw TestFailure("failed to create isolated UserDefaults suites")
        }
        defer {
            newDefaults.removePersistentDomain(forName: suiteName)
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }

        legacyDefaults.set(true, forKey: "languageOverride")
        AppIdentityMigration.migrateLegacyBoolKey(
            "languageOverride",
            userDefaults: newDefaults,
            legacyDefaults: legacyDefaults
        )

        expect(newDefaults.object(forKey: "languageOverride") != nil, "language override should migrate from legacy defaults")
        expect(newDefaults.bool(forKey: "languageOverride"), "language override migrated value should be preserved")
    }

    private static func testLocalUsageCacheDirectoryMigration() throws {
        let tempRoot = try makeTemporaryDirectory(named: "ccusage-cache")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let legacyURL = tempRoot.appendingPathComponent(AppIdentity.legacyLocalUsageCacheDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try Data("cached".utf8).write(to: legacyURL.appendingPathComponent("marker.txt"))

        let currentURL = AppIdentityMigration.localUsageCacheDirectory(
            fileManager: .default,
            baseDirectory: tempRoot
        )

        expect(currentURL.lastPathComponent == "relaybar-ccusage", "local usage cache should use RelayBar directory name")
        expect(FileManager.default.fileExists(atPath: currentURL.appendingPathComponent("marker.txt").path), "legacy ccusage cache contents should migrate")
        expect(!FileManager.default.fileExists(atPath: legacyURL.path), "legacy ccusage cache directory should be moved when possible")
    }

    private static func sampleTokens(accountId: String, subject: String, email: String) -> OAuthTokens {
        let accessPayload: [String: Any] = [
            "exp": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountId,
                "chatgpt_plan_type": "team",
            ]
        ]
        let idPayload: [String: Any] = [
            "sub": subject,
            "email": email,
        ]

        return OAuthTokens(
            accessToken: makeJWT(payload: accessPayload),
            refreshToken: "refresh-\(subject)",
            idToken: makeJWT(payload: idPayload)
        )
    }

    private static func sampleAntigravityAccount(
        id: String,
        email: String,
        tier: String,
        isActive: Bool = false
    ) -> AntigravityAccount {
        AntigravityAccount(
            id: id,
            email: email,
            name: email,
            token: AntigravityTokenData(
                accessToken: "access-\(id)",
                refreshToken: "refresh-\(id)",
                expiresIn: 3600,
                email: email,
                projectId: "project-\(id)"
            ),
            deviceProfile: AntigravityDeviceProfile(
                machineId: "auth0|user_\(id)",
                macMachineId: "mac-\(id)",
                devDeviceId: "dev-\(id)",
                sqmId: "{\(id.uppercased())}"
            ),
            localStateSnapshot: AntigravityLocalStateSnapshot(
                stateItems: [
                    "antigravityUnifiedStateSync.oauthToken": "oauth-row-\(id)",
                    "antigravityUnifiedStateSync.userStatus": "user-row-\(id)"
                ],
                missingStateKeys: [
                    "antigravityUnifiedStateSync.enterprisePreferences",
                    "antigravityAuthStatus",
                    "jetskiStateSync.agentManagerInitState",
                    "google.antigravity",
                    "antigravityOnboarding"
                ],
                capturedAt: Date(timeIntervalSince1970: 100)
            ),
            quota: AntigravityQuotaData(
                models: [
                    AntigravityModelQuota(
                        name: "claude-sonnet-4-6",
                        remainingPercent: 50,
                        resetTime: "2026-04-22T17:37:54Z",
                        displayName: "Claude Sonnet 4.6 (Thinking)"
                    )
                ],
                subscriptionTier: tier
            ),
            isActive: isActive
        )
    }

    private static func tokenCountLine(timestamp: String, totalTokens: Int) -> String {
        let inputTokens = totalTokens / 2
        let outputTokens = totalTokens - inputTokens
        return """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"total_tokens":\(totalTokens)}}}}
        """
    }

    private static func requiredItem(
        in items: [CredentialTransferSelectableItem],
        where predicate: (CredentialTransferSelectableItem) -> Bool
    ) throws -> CredentialTransferSelectableItem {
        guard let item = items.first(where: predicate) else {
            throw TestFailure("expected selectable item was not found")
        }
        return item
    }

    private static func makePaths(root: URL) -> CodexPaths {
        let defaultCodexHomeURL = root.appendingPathComponent(".codex", isDirectory: true)
        let configuredCodexHomeURL = root.appendingPathComponent("custom-codex", isDirectory: true)
        let legacyCodexConfigURL = root.appendingPathComponent(".config/codex", isDirectory: true)

        return CodexPaths(
            realHomeURL: root,
            defaultCodexHomeURL: defaultCodexHomeURL,
            configuredCodexHomeURL: configuredCodexHomeURL,
            legacyCodexConfigURL: legacyCodexConfigURL,
            authReadCandidates: [
                configuredCodexHomeURL.appendingPathComponent("auth.json"),
                defaultCodexHomeURL.appendingPathComponent("auth.json"),
                legacyCodexConfigURL.appendingPathComponent("auth.json"),
            ],
            authWriteTargets: [
                defaultCodexHomeURL.appendingPathComponent("auth.json"),
                configuredCodexHomeURL.appendingPathComponent("auth.json"),
            ]
        )
    }

    private static func makeAntigravityPaths(root: URL) -> AntigravityPaths {
        let codexHomeURL = root.appendingPathComponent(".codex", isDirectory: true)
        let storageURL = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Antigravity", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)

        return AntigravityPaths(
            realHomeURL: root,
            codexHomeURL: codexHomeURL,
            poolURL: codexHomeURL.appendingPathComponent("antigravity_pool.json"),
            antigravityGlobalStorageURL: storageURL,
            storageJSONURL: storageURL.appendingPathComponent("storage.json"),
            stateDatabaseURL: storageURL.appendingPathComponent("state.vscdb")
        )
    }

    private static func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relaybar-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func posixPermissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw TestFailure("missing POSIX permissions for \(url.path)")
        }
        return permissions.intValue
    }

    private static func makeJWT(payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return [
            base64URL(headerData),
            base64URL(payloadData),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    private final class InMemoryAntigravityOAuthConfigStore: AntigravityOAuthConfigStore {
        private var storedConfig: AntigravityOAuthConfig?

        func load() throws -> AntigravityOAuthConfig? {
            storedConfig
        }

        func save(_ config: AntigravityOAuthConfig) throws {
            storedConfig = config
        }

        func delete() throws {
            storedConfig = nil
        }
    }
}

private struct TestFailure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        self.errorDescription = message
    }
}
