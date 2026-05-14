import Foundation

struct CodexUsageSnapshot {
    let planType: String
    let primaryUsedPercent: Double
    let secondaryUsedPercent: Double
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let organizationName: String?
    let usageSnapshot: UsageSnapshot?
}

enum CodexUsageFetchResult {
    case success(CodexUsageSnapshot)
    case tokenExpired
    case suspended
    case retryableFailure(String)
    case parseFailure
}

final class CodexUsageClient {
    static let shared = CodexUsageClient()

    private let session: URLSession
    private let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    private let organizationURL = "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27?timezone_offset_min=-480"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(for account: TokenAccount) async -> CodexUsageFetchResult {
        let usageResponse = await fetchJSON(from: usageURL, account: account)
        switch usageResponse {
        case .success(let json):
            guard let usage = parseUsage(json) else {
                return .parseFailure
            }

            let organizationName: String?
            switch await fetchJSON(from: organizationURL, account: account) {
            case .success(let orgJSON):
                organizationName = parseOrganizationName(orgJSON, accountId: account.accountId)
            case .failure:
                organizationName = nil
            }

            return .success(
                CodexUsageSnapshot(
                    planType: usage.planType,
                    primaryUsedPercent: usage.primaryUsedPercent,
                    secondaryUsedPercent: usage.secondaryUsedPercent,
                    primaryResetAt: usage.primaryResetAt,
                    secondaryResetAt: usage.secondaryResetAt,
                    organizationName: organizationName,
                    usageSnapshot: usage.usageSnapshot
                )
            )
        case .failure(let error):
            switch error {
            case .unauthorized:
                return .tokenExpired
            case .suspended:
                return .suspended
            case .retryable(let message):
                return .retryableFailure(message)
            case .parse:
                return .parseFailure
            }
        }
    }

    private func fetchJSON(from urlString: String, account: TokenAccount) async -> Result<[String: Any], RemoteFetchError> {
        guard let url = URL(string: urlString) else {
            return .failure(.retryable("请求地址无效"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(account.accountId, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN", forHTTPHeaderField: "oai-language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.retryable(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.retryable("无效响应"))
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            return .failure(.unauthorized)
        case 402, 403:
            return .failure(.suspended)
        default:
            return .failure(.retryable("HTTP \(http.statusCode)"))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.parse)
        }
        return .success(json)
    }

    private func parseUsage(_ json: [String: Any]) -> WhamUsageResult? {
        let planType = json["plan_type"] as? String ?? "free"
        let coreGroup = parseRateLimitGroup(
            rateLimit: json["rate_limit"] as? [String: Any],
            rawLimitName: json["rate_limit_name"] as? String,
            blocked: isBlocked(json["rate_limit"] as? [String: Any])
        )

        let additionalGroups = (json["additional_rate_limits"] as? [[String: Any]] ?? []).compactMap { entry in
            parseRateLimitGroup(
                rateLimit: entry["rate_limit"] as? [String: Any],
                rawLimitName: entry["limit_name"] as? String,
                blocked: isBlocked(entry["rate_limit"] as? [String: Any])
            )
        }

        let usageSnapshot = UsageSnapshot(
            rateLimitGroups: [coreGroup].compactMap { $0 } + additionalGroups,
            credits: parseCredits(json["credits"] as? [String: Any])
        )

        let primaryWindow = usageSnapshot.coreGroup?.closestWindow(to: 300)
        let secondaryWindow = usageSnapshot.coreGroup?.closestWindow(to: 7 * 1440)

        return WhamUsageResult(
            planType: planType,
            primaryUsedPercent: primaryWindow?.usedPercent ?? 0,
            secondaryUsedPercent: secondaryWindow?.usedPercent ?? 0,
            primaryResetAt: primaryWindow?.resetAt,
            secondaryResetAt: secondaryWindow?.resetAt,
            usageSnapshot: usageSnapshot.hasStructuredContent ? usageSnapshot : nil
        )
    }

    private func parseOrganizationName(_ json: [String: Any], accountId: String) -> String? {
        guard
            let accounts = json["accounts"] as? [String: Any],
            let entry = accounts[accountId] as? [String: Any],
            let account = entry["account"] as? [String: Any],
            let name = account["name"] as? String
        else {
            return nil
        }
        return name
    }

    private func parseRateLimitGroup(
        rateLimit: [String: Any]?,
        rawLimitName: String?,
        blocked: Bool
    ) -> UsageRateLimitGroup? {
        let primaryWindow = parseWindow(rateLimit?["primary_window"] as? [String: Any])
        let secondaryWindow = parseWindow(rateLimit?["secondary_window"] as? [String: Any])

        guard primaryWindow != nil || secondaryWindow != nil || blocked else {
            return nil
        }

        return UsageRateLimitGroup(
            limitName: UsageRateLimitGroup.normalizedLimitName(rawLimitName),
            blocked: blocked,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )
    }

    private func parseWindow(_ json: [String: Any]?) -> UsageWindowSnapshot? {
        guard let json else { return nil }
        return UsageWindowSnapshot(
            usedPercent: doubleValue(json["used_percent"]) ?? 0,
            windowDurationMinutes: intValue(json["limit_window_seconds"]).map { max($0 / 60, 1) },
            resetAt: dateValue(json["reset_at"])
        )
    }

    private func parseCredits(_ json: [String: Any]?) -> UsageCreditsSnapshot? {
        guard let json else { return nil }
        return UsageCreditsSnapshot(
            hasCredits: boolValue(json["has_credits"]) ?? false,
            unlimited: boolValue(json["unlimited"]) ?? false,
            balance: doubleValue(json["balance"])
        )
    }

    private func isBlocked(_ rateLimit: [String: Any]?) -> Bool {
        guard let rateLimit else { return false }
        return (boolValue(rateLimit["limit_reached"]) ?? false) || (boolValue(rateLimit["allowed"]) == false)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return NSString(string: value).boolValue
        default:
            return nil
        }
    }

    private func dateValue(_ value: Any?) -> Date? {
        guard let seconds = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

private enum RemoteFetchError: Error {
    case unauthorized
    case suspended
    case retryable(String)
    case parse
}
