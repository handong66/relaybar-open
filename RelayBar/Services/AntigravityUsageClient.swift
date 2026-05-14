import Foundation

struct AntigravityUsageSnapshot {
    var quota: AntigravityQuotaData
    var projectId: String?
}

enum AntigravityUsageFetchResult {
    case success(AntigravityUsageSnapshot)
    case tokenExpired
    case forbidden(String?)
    case retryableFailure(String)
    case parseFailure
}

final class AntigravityUsageClient {
    static let shared = AntigravityUsageClient()

    private let session: URLSession
    private let oauthClient: AntigravityOAuthClient
    private let quotaEndpoints = [
        "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:fetchAvailableModels",
        "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels",
        "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    ]

    init(
        session: URLSession = .shared,
        oauthClient: AntigravityOAuthClient = .shared
    ) {
        self.session = session
        self.oauthClient = oauthClient
    }

    func fetchSnapshot(for account: AntigravityAccount) async -> AntigravityUsageFetchResult {
        let metadata: AntigravityProjectMetadata?
        if let cachedProjectId = account.token.projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedProjectId.isEmpty,
           let cachedTier = account.quota?.subscriptionTier,
           !cachedTier.isEmpty {
            metadata = AntigravityProjectMetadata(projectId: cachedProjectId, subscriptionTier: account.quota?.subscriptionTier)
        } else {
            metadata = try? await oauthClient.fetchProjectMetadata(accessToken: account.token.accessToken)
        }

        let payload: [String: Any]
        if let projectId = metadata?.projectId, !projectId.isEmpty {
            payload = ["project": projectId]
        } else {
            payload = [:]
        }

        var lastError: String?
        for (index, endpoint) in quotaEndpoints.enumerated() {
            switch await fetchQuota(endpoint: endpoint, accessToken: account.token.accessToken, payload: payload) {
            case .success(let quota):
                var updatedQuota = quota
                if let tier = metadata?.subscriptionTier, !tier.isEmpty {
                    updatedQuota.subscriptionTier = tier
                }
                return .success(AntigravityUsageSnapshot(quota: updatedQuota, projectId: metadata?.projectId))
            case .failure(let error):
                switch error {
                case .unauthorized:
                    return .tokenExpired
                case .forbidden(let reason):
                    return .forbidden(reason)
                case .parse:
                    return .parseFailure
                case .retryable(let message):
                    lastError = message
                    if index + 1 < quotaEndpoints.count {
                        continue
                    }
                    return .retryableFailure(message)
                }
            }
        }

        return .retryableFailure(lastError ?? "Antigravity 额度请求失败")
    }

    private func fetchQuota(
        endpoint: String,
        accessToken: String,
        payload: [String: Any]
    ) async -> Result<AntigravityQuotaData, AntigravityRemoteFetchError> {
        guard let url = URL(string: endpoint) else {
            return .failure(.retryable("Antigravity 额度地址无效"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AntigravityOAuthClient.nativeOAuthUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.retryable(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.retryable("Antigravity 额度响应无效"))
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            return .failure(.unauthorized)
        case 403:
            return .failure(.forbidden(String(data: data, encoding: .utf8)))
        case 429, 500...599:
            return .failure(.retryable("Antigravity 额度服务暂不可用: HTTP \(http.statusCode)"))
        default:
            return .failure(.retryable("Antigravity 额度请求失败: HTTP \(http.statusCode)"))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.parse)
        }

        return parseQuota(json)
            .map(Result.success)
            ?? .failure(.parse)
    }

    private func parseQuota(_ json: [String: Any]) -> AntigravityQuotaData? {
        guard let models = json["models"] as? [String: Any] else {
            return nil
        }

        let parsedModels = models.compactMap { name, rawValue -> AntigravityModelQuota? in
            guard
                let modelJSON = rawValue as? [String: Any],
                let quotaInfo = modelJSON["quotaInfo"] as? [String: Any]
            else {
                return nil
            }

            let remainingFraction = doubleValue(quotaInfo["remainingFraction"]) ?? 0
            let remainingPercent = min(max(Int((remainingFraction * 100).rounded()), 0), 100)
            let resetTime = quotaInfo["resetTime"] as? String ?? ""

            return AntigravityModelQuota(
                name: name,
                remainingPercent: remainingPercent,
                resetTime: resetTime,
                displayName: modelJSON["displayName"] as? String,
                supportsImages: boolValue(modelJSON["supportsImages"]),
                supportsThinking: boolValue(modelJSON["supportsThinking"]),
                thinkingBudget: intValue(modelJSON["thinkingBudget"]),
                recommended: boolValue(modelJSON["recommended"]),
                maxTokens: intValue(modelJSON["maxTokens"]),
                maxOutputTokens: intValue(modelJSON["maxOutputTokens"])
            )
        }

        return AntigravityQuotaData(
            models: parsedModels,
            lastUpdated: Date()
        )
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
}

private enum AntigravityRemoteFetchError: Error {
    case unauthorized
    case forbidden(String?)
    case retryable(String)
    case parse
}
