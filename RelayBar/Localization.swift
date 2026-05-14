import Foundation

/// Bilingual string helper — detects system language at runtime, with user override.
enum L {
    /// nil = follow system, true = force Chinese, false = force English
    static var languageOverride: Bool? {
        get {
            AppIdentityMigration.migrateLegacyLanguageOverride()
            let d = UserDefaults.standard
            guard d.object(forKey: "languageOverride") != nil else { return nil }
            return d.bool(forKey: "languageOverride")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "languageOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "languageOverride")
            }
        }
    }

    static var zh: Bool {
        if let override = languageOverride { return override }
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        return lang.hasPrefix("zh")
    }

    static func nextLanguageOverride(currentOverride: Bool?, resolvedZh: Bool) -> Bool? {
        !resolvedZh
    }

    // MARK: - MenuBarView
    static var noAccounts: String      { zh ? "还没有账号"          : "No Accounts" }
    static var refreshUsage: String    { zh ? "刷新用量"            : "Refresh Usage" }
    static var addAccount: String      { zh ? "添加账号"            : "Add Account" }
    static var importAccount: String   { zh ? "导入当前登录"         : "Import Current Login" }
    static var configureOAuth: String { zh ? "授权配置" : "OAuth Setup" }
    static var exportCredentials: String { zh ? "导出凭证" : "Export Credentials" }
    static var importCredentials: String { zh ? "导入凭证" : "Import Credentials" }
    static var credentialsSelectAccountsTitle: String { zh ? "选择要导出的账号" : "Select Accounts to Export" }
    static var credentialsImportPreviewTitle: String { zh ? "选择要导入的账号" : "Select Accounts to Import" }
    static var credentialsNoAccountsSelected: String { zh ? "请至少选择一个账号" : "Select at least one account" }
    static var credentialsBundleEmpty: String { zh ? "凭证包中没有可导入的账号" : "No accounts found in this credential bundle" }
    static var credentialsExportWarning: String { zh ? "导出的文件包含明文 access / refresh token，请妥善保管。" : "This export contains plaintext access / refresh tokens. Store it securely." }
    static var credentialsImportHelp: String { zh ? "选择之前导出的 RelayBar 凭证包。" : "Choose a previously exported RelayBar credential bundle." }
    static var credentialsExportFailed: String { zh ? "导出凭证包失败" : "Failed to export credential bundle" }
    static var credentialsInvalidBundle: String { zh ? "凭证包格式无效" : "Credential bundle format is invalid" }
    static var credentialsConflictOverwrite: String { zh ? "覆盖本机" : "Overwrite Local" }
    static var credentialsConflictKeepLocal: String { zh ? "保留本机" : "Keep Local" }
    static var credentialsConflictLabel: String { zh ? "重复账号处理" : "Duplicate handling" }
    static var credentialsDuplicateBadge: String { zh ? "重复" : "Duplicate" }
    static var credentialsActiveBadge: String { zh ? "激活" : "Active" }
    static var credentialsSelectAll: String { zh ? "全选" : "Select All" }
    static var credentialsDeselectAll: String { zh ? "全不选" : "Clear All" }
    static var credentialsSelectedCount: String { zh ? "已选" : "Selected" }
    static var credentialsExportConfirm: String { zh ? "继续导出" : "Continue Export" }
    static var credentialsImportConfirm: String { zh ? "开始导入" : "Import Selected" }
    static var credentialsImportDescription: String { zh ? "勾选要写入本机的账号；重复账号可逐个决定覆盖还是保留本机。" : "Choose which accounts to import. For duplicates, decide per account whether to overwrite local data or keep the local copy." }
    static var credentialsExportDescription: String { zh ? "勾选要写入凭证包的账号。可混合导出 Codex 与 Antigravity 账号。" : "Choose which accounts to include in the credential bundle. Codex and Antigravity accounts can be mixed in one file." }
    static func credentialsUnsupportedBundleVersion(_ version: Int) -> String {
        zh ? "不支持的凭证包版本: \(version)" : "Unsupported credential bundle version: \(version)"
    }
    static func credentialsExported(_ name: String, _ count: Int) -> String {
        zh ? "已导出 \(count) 个账号到: \(name)" : "Exported \(count) accounts to: \(name)"
    }
    static func credentialsImported(
        codexAdded: Int,
        codexOverwritten: Int,
        codexSkipped: Int,
        antigravityAdded: Int,
        antigravityOverwritten: Int,
        antigravitySkipped: Int
    ) -> String {
        if zh {
            return "导入完成。Codex 新增 \(codexAdded) / 覆盖 \(codexOverwritten) / 跳过 \(codexSkipped)，Antigravity 新增 \(antigravityAdded) / 覆盖 \(antigravityOverwritten) / 跳过 \(antigravitySkipped)"
        }
        return "Import complete. Codex added \(codexAdded) / overwritten \(codexOverwritten) / skipped \(codexSkipped), Antigravity added \(antigravityAdded) / overwritten \(antigravityOverwritten) / skipped \(antigravitySkipped)"
    }
    static var quit: String            { zh ? "退出"               : "Quit" }
    static var cancel: String          { zh ? "取消"               : "Cancel" }
    static var justUpdated: String     { zh ? "刚刚更新"            : "Just updated" }
    static var menuRefreshingNow: String { zh ? "正在刷新最新额度" : "Refreshing the latest usage" }
    static var menuCurrentAccountTitle: String { zh ? "当前账号" : "Current Account" }
    static var menuOtherAccountsTitle: String { zh ? "其他账号" : "Other Accounts" }
    static var menuShowLessAccounts: String { zh ? "收起" : "Show Less" }
    static func menuShowMoreAccounts(_ count: Int) -> String {
        zh ? "展开其余 \(count) 个" : "Show \(count) More"
    }
    static func menuShowExtraModels(_ count: Int) -> String {
        zh ? "+\(count) 个模型" : "+\(count) models"
    }
    static var menuHideExtraModels: String { zh ? "收起附加模型" : "Hide Extra Models" }
    static var menuMoreModelsTitle: String { zh ? "附加模型" : "More Models" }
    static var menuCodexEmptyDescription: String { zh ? "从这里添加 Codex 账号，或导入另一台机器导出的凭证包。" : "Add a Codex account here, or import a credential bundle exported from another Mac." }
    static var menuAntigravityEmptyDescription: String { zh ? "添加 Antigravity 账号、导入当前登录，或直接导入凭证包。" : "Add an Antigravity account, import the current login, or import a credential bundle." }

    static func available(_ n: Int, _ total: Int) -> String {
        zh ? "\(n)/\(total) 可用" : "\(n)/\(total) Available"
    }
    static func minutesAgo(_ m: Int) -> String {
        zh ? "\(m) 分钟前更新" : "Updated \(m) min ago"
    }
    static func hoursAgo(_ h: Int) -> String {
        zh ? "\(h) 小时前更新" : "Updated \(h) hr ago"
    }
    // MARK: - AccountRowView
    static var reauth: String          { zh ? "重新授权"     : "Re-authorize" }
    static var switchBtn: String       { zh ? "切换"         : "Switch" }
    static func confirmDelete(_ name: String) -> String {
        zh ? "确认删除 \(name)？" : "Delete \(name)?"
    }
    static var delete: String         { zh ? "删除"     : "Delete" }
    static var tokenExpiredHint: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var accountSuspended: String { zh ? "账号已停用" : "Account suspended" }
    static var weeklyExhausted: String  { zh ? "周额度耗尽" : "Weekly quota exhausted" }
    static var primaryExhausted: String { zh ? "5h 额度耗尽" : "5h quota exhausted" }
    static var weeklyExhaustedShort: String { zh ? "每周用尽" : "Weekly empty" }
    static var primaryExhaustedShort: String { zh ? "5h 用尽" : "5h empty" }
    static var usageTitle: String { zh ? "用量" : "Usage" }
    static var usageSessionTitle: String { zh ? "会话" : "Session" }
    static var usageWeeklyTitle: String { zh ? "每周" : "Weekly" }
    static var usageCreditsTitle: String { zh ? "Credits" : "Credits" }
    static var usageLocalUsageTitle: String { zh ? "本机使用" : "Local Usage" }
    static var usageTodayTitle: String { zh ? "今天" : "Today" }
    static var usageYesterdayTitle: String { zh ? "昨天" : "Yesterday" }
    static var usageLastThirtyDaysTitle: String { zh ? "过去 30 天" : "Last 30 Days" }
    static var usageStatusLabel: String { zh ? "状态" : "Status" }
    static var usageBlockedBadge: String { zh ? "受限" : "Blocked" }
    static var usageUnlimitedBadge: String { zh ? "无限" : "Unlimited" }
    static var usageAvailableBadge: String { zh ? "可用" : "Available" }
    static var usageLowBadge: String { zh ? "偏低" : "Low" }
    static var usageEmptyBadge: String { zh ? "为空" : "Empty" }
    static var usageCreditsUnlimited: String { zh ? "无限 credits" : "Unlimited credits" }
    static var usageCreditsUnavailable: String { zh ? "credits 信息不可用" : "Credits unavailable" }
    static var usageCreditsBalanceLabel: String { zh ? "余额" : "Balance" }
    static var usageCreditsStatusLabel: String { zh ? "额度" : "Credits" }
    static func usageCreditsBalanceValue(_ value: String) -> String {
        zh ? "\(value) credits" : "\(value) credits"
    }
    static func usageLeftValue(_ value: String) -> String {
        zh ? "剩余 \(value)" : "\(value) left"
    }
    static func usageTokenCountValue(_ value: String) -> String {
        zh ? "\(value) tokens" : "\(value) tokens"
    }
    static func usageRecentUsageValue(_ cost: String, _ tokens: String) -> String {
        "\(cost) · \(tokens)"
    }
    static var usageUnknownWindow: String { zh ? "窗口" : "Window" }
    static var providerCodex: String { "Codex" }
    static var providerAntigravity: String { "Antigravity" }
    static var antigravityQuotaTitle: String { zh ? "模型额度" : "Model Quota" }
    static var antigravityForbidden: String { zh ? "不可用" : "Forbidden" }
    static var antigravitySwitchComplete: String { zh ? "Antigravity 账号已切换，请重新打开 Antigravity" : "Antigravity account switched. Reopen Antigravity to continue." }
    static var antigravityNoQuota: String { zh ? "暂无额度数据，点刷新获取" : "No quota yet. Refresh to fetch usage." }
    static var antigravityImportHelp: String { zh ? "从当前 Antigravity 登录状态导入账号" : "Import the current Antigravity login" }
    static var antigravityOAuthConfigurationMissing: String {
        zh
            ? "请先配置 Antigravity Google OAuth client。可点“授权配置”，或使用环境变量 / ~/.config/relaybar/antigravity-oauth.json。"
            : "Configure an Antigravity Google OAuth client first. Use OAuth Setup, environment variables, or ~/.config/relaybar/antigravity-oauth.json."
    }
    static func antigravityOAuthConfigurationInvalid(_ message: String) -> String {
        zh ? "Antigravity OAuth 配置无效: \(message)" : "Antigravity OAuth configuration is invalid: \(message)"
    }
    static func antigravityOAuthKeychainError(_ message: String) -> String {
        zh ? "Antigravity OAuth 凭据保存失败: \(message)" : "Failed to save Antigravity OAuth credentials: \(message)"
    }
    static var antigravityOAuthConfigTitle: String { zh ? "Antigravity OAuth 配置" : "Antigravity OAuth Setup" }
    static var antigravityOAuthConfigDescription: String {
        zh
            ? "填写你自己的 Google OAuth client。RelayBar 会把它保存到本机 Keychain，不会写入仓库或凭证导出包。"
            : "Enter your own Google OAuth client. RelayBar stores it in the local Keychain, not in the repository or credential exports."
    }
    static var antigravityOAuthClientIdLabel: String { zh ? "Google Client ID" : "Google Client ID" }
    static var antigravityOAuthClientSecretLabel: String { zh ? "Google Client Secret" : "Google Client Secret" }
    static var antigravityOAuthCloudCodeBaseURLLabel: String { zh ? "Cloud Code Base URL" : "Cloud Code Base URL" }
    static var antigravityOAuthCloudCodeBaseURLHelp: String {
        zh ? "通常保持默认即可。" : "The default is usually correct."
    }
    static var antigravityOAuthSave: String { zh ? "保存到 Keychain" : "Save to Keychain" }
    static var antigravityOAuthSaved: String { zh ? "Antigravity OAuth 配置已保存。" : "Antigravity OAuth configuration saved." }
    static var antigravityOAuthClear: String { zh ? "清除 Keychain 配置" : "Clear Keychain Config" }
    static var antigravityOAuthCleared: String { zh ? "Keychain 中的 Antigravity OAuth 配置已清除。" : "Antigravity OAuth configuration removed from Keychain." }
    static var antigravityCurrentLoginImported: String {
        zh ? "已导入当前 Antigravity 登录；如需更新额度，请重新打开 Antigravity 后刷新。" : "Imported the current Antigravity login. Reopen Antigravity before refreshing usage."
    }
    static var antigravityCurrentLoginReauthorized: String {
        zh ? "已使用当前 Antigravity 登录更新账号。" : "Updated the account from the current Antigravity login."
    }
    static func antigravityCurrentLoginUpdatedDifferent(expected: String, actual: String) -> String {
        zh
            ? "当前 Antigravity 登录是 \(actual)，已更新该账号。若要更新 \(expected)，请先在官方 Antigravity 登录它。"
            : "The current Antigravity login is \(actual), so that account was updated. To update \(expected), sign in to it in Antigravity first."
    }
    static func antigravityCurrentLoginMismatch(expected: String, actual: String) -> String {
        zh
            ? "当前 Antigravity 登录是 \(actual)，不是 \(expected)。请先在官方 Antigravity 登录这个账号，再点重新授权。"
            : "The current Antigravity login is \(actual), not \(expected). Sign in to that account in Antigravity first, then re-authorize."
    }
    static func antigravityReauthNeedsOfficialLogin(account: String) -> String {
        zh
            ? "已打开 Antigravity。请先在官方 Antigravity 登录 \(account)，再回 RelayBar 点重新授权。"
            : "Antigravity has been opened. Sign in to \(account) in the official Antigravity app, then return to RelayBar and re-authorize."
    }
    static var antigravityRefreshNeedsCurrentLogin: String {
        zh
            ? "请先在官方 Antigravity 登录该账号，再回 RelayBar 导入当前登录或重新授权。"
            : "Sign in to this account in the official Antigravity app, then import the current login or re-authorize in RelayBar."
    }
    static func usageMinutesWindow(_ minutes: Int) -> String {
        zh ? "\(minutes) 分钟" : "\(minutes)m"
    }
    static func usageHoursWindow(_ hours: Int) -> String {
        zh ? "\(hours) 小时" : "\(hours)h"
    }
    static func usageHourMinuteWindow(_ hours: Int, _ minutes: Int) -> String {
        zh ? "\(hours) 小时 \(minutes) 分钟" : "\(hours)h \(minutes)m"
    }
    static func usageDaysWindow(_ days: Int) -> String {
        zh ? "\(days) 天" : "\(days)d"
    }
    static func usageHourWindowApprox(_ hours: Int) -> String {
        zh ? "\(hours) 小时" : "\(hours)h"
    }

    // MARK: - Reset countdown
    static var resetSoon: String { zh ? "即将重置" : "Resetting soon" }
    static func resetInMin(_ m: Int) -> String {
        zh ? "\(m) 分钟后重置" : "Resets in \(m) min"
    }
    static func resetInHr(_ h: Int, _ m: Int) -> String {
        zh ? "\(h) 小时 \(m) 分后重置" : "Resets in \(h)h \(m)m"
    }
    static func resetInDay(_ d: Int, _ h: Int) -> String {
        zh ? "\(d) 天 \(h) 小时后重置" : "Resets in \(d)d \(h)h"
    }
}
