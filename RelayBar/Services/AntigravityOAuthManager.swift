import AppKit
import Combine
import Foundation

class AntigravityOAuthManager: NSObject, ObservableObject {
    static let shared = AntigravityOAuthManager()

    @Published var isAuthenticating = false
    @Published var errorMessage: String?

    private let oauthClient = AntigravityOAuthClient.shared
    private let callbackPort: UInt16 = 1456
    private var expectedState = ""
    private var localServer: LocalCallbackServer?
    private var completionHandler: ((Result<AntigravityAccount, Error>) -> Void)?

    func startOAuth(completion: @escaping (Result<AntigravityAccount, Error>) -> Void) {
        isAuthenticating = true
        errorMessage = nil
        completionHandler = completion
        expectedState = UUID().uuidString

        let redirectURI = "http://localhost:\(callbackPort)/auth/callback"
        let url: URL
        do {
            url = try oauthClient.authorizationURL(redirectURI: redirectURI, state: expectedState)
        } catch {
            fail(error)
            return
        }

        localServer = LocalCallbackServer(port: callbackPort)
        localServer?.start { [weak self] code, returnedState in
            guard let self else { return }
            guard returnedState == self.expectedState else {
                self.fail(AntigravityOAuthError.stateMismatch)
                return
            }
            self.exchangeCode(code, redirectURI: redirectURI)
        }

        NSWorkspace.shared.open(url)
    }

    func cancel() {
        localServer?.stop()
        localServer = nil
        isAuthenticating = false
        completionHandler = nil
    }

    private func exchangeCode(_ code: String, redirectURI: String) {
        Task {
            do {
                let tokenResponse = try await oauthClient.exchangeCode(code, redirectURI: redirectURI)
                guard let refreshToken = tokenResponse.refreshToken, !refreshToken.isEmpty else {
                    throw AntigravityOAuthError.noRefreshToken
                }

                let userInfo = try await oauthClient.fetchUserInfo(accessToken: tokenResponse.accessToken)
                let metadata = try? await oauthClient.fetchProjectMetadata(accessToken: tokenResponse.accessToken)
                let token = AntigravityTokenData(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: refreshToken,
                    expiresIn: tokenResponse.expiresIn,
                    email: userInfo.email,
                    projectId: metadata?.projectId,
                    oauthClientKey: AntigravityOAuthClient.defaultClientKey,
                    isGcpTos: true,
                    idToken: tokenResponse.idToken,
                    tokenType: tokenResponse.tokenType
                )

                let account = AntigravityAccount(
                    email: userInfo.email,
                    name: userInfo.displayName,
                    token: token,
                    deviceProfile: AntigravityDeviceProfile.generate()
                )

                await MainActor.run {
                    self.localServer?.stop()
                    self.localServer = nil
                    self.isAuthenticating = false
                    self.completionHandler?(.success(account))
                    self.completionHandler = nil
                }
            } catch {
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            self.localServer?.stop()
            self.localServer = nil
            self.isAuthenticating = false
            self.errorMessage = error.localizedDescription
            self.completionHandler?(.failure(error))
            self.completionHandler = nil
        }
    }
}

final class AntigravityTokenRefresher {
    static let shared = AntigravityTokenRefresher()

    private let oauthClient: AntigravityOAuthClient

    init(oauthClient: AntigravityOAuthClient = .shared) {
        self.oauthClient = oauthClient
    }

    func refresh(token: AntigravityTokenData) async throws -> AntigravityTokenData {
        let response = try await oauthClient.refreshAccessToken(refreshToken: token.refreshToken)
        return AntigravityTokenData(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? token.refreshToken,
            expiresIn: response.expiresIn,
            email: token.email,
            projectId: token.projectId,
            oauthClientKey: token.oauthClientKey ?? AntigravityOAuthClient.defaultClientKey,
            isGcpTos: token.isGcpTos,
            idToken: response.idToken ?? token.idToken,
            tokenType: response.tokenType.isEmpty ? token.tokenType : response.tokenType
        )
    }

    func refresh(account: AntigravityAccount) async throws -> AntigravityAccount {
        var updated = account
        let refreshedToken = try await refresh(token: account.token)
        let userInfo = try? await oauthClient.fetchUserInfo(accessToken: refreshedToken.accessToken)

        updated.token = refreshedToken
        if let userInfo {
            updated.email = userInfo.email
            updated.name = userInfo.displayName ?? updated.name
            updated.token.email = userInfo.email
        }
        if updated.token.projectId == nil {
            updated.token.projectId = try? await oauthClient.fetchProjectId(accessToken: refreshedToken.accessToken)
        }
        return updated
    }
}

final class AntigravityOAuthClient {
    static let shared = AntigravityOAuthClient()
    static let defaultClientKey = "antigravity_enterprise"
    static let defaultCloudCodeBaseURL = "https://daily-cloudcode-pa.sandbox.googleapis.com"

    private let session: URLSession
    private let configResolver: AntigravityOAuthConfigResolver
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"

    private let scopes = [
        "openid",
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs"
    ].joined(separator: " ")

    init(
        session: URLSession = .shared,
        configResolver: AntigravityOAuthConfigResolver = .shared
    ) {
        self.session = session
        self.configResolver = configResolver
    }

    func authorizationURL(redirectURI: String, state: String) throws -> URL {
        let config = try configResolver.load()
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.googleClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else {
            throw AntigravityOAuthError.invalidURL
        }
        return url
    }

    func exchangeCode(_ code: String, redirectURI: String) async throws -> AntigravityOAuthTokenResponse {
        let config = try configResolver.load()
        let body = [
            "client_id": config.googleClientId,
            "client_secret": config.googleClientSecret,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        return try await postForm(urlString: tokenURL, body: body)
    }

    func refreshAccessToken(refreshToken: String) async throws -> AntigravityOAuthTokenResponse {
        let config = try configResolver.load()
        let body = [
            "client_id": config.googleClientId,
            "client_secret": config.googleClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        return try await postForm(urlString: tokenURL, body: body)
    }

    func fetchUserInfo(accessToken: String) async throws -> AntigravityGoogleUserInfo {
        guard let url = URL(string: userInfoURL) else {
            throw AntigravityOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(AntigravityGoogleUserInfo.self, from: data)
    }

    func fetchProjectId(accessToken: String) async throws -> String? {
        try await fetchProjectMetadata(accessToken: accessToken).projectId
    }

    func fetchProjectMetadata(accessToken: String) async throws -> AntigravityProjectMetadata {
        let baseURL = (try? configResolver.load().cloudCodeBaseURL) ?? Self.defaultCloudCodeBaseURL
        guard let url = URL(string: "\(baseURL)/v1internal:loadCodeAssist") else {
            throw AntigravityOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.nativeOAuthUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": ["ideType": "ANTIGRAVITY"]
        ])

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AntigravityOAuthError.invalidResponse
        }
        return AntigravityProjectMetadata(
            projectId: json["cloudaicompanionProject"] as? String,
            subscriptionTier: subscriptionTier(from: json)
        )
    }

    private func postForm<T: Decodable>(urlString: String, body: [String: String]) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw AntigravityOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.nativeOAuthUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formEncoded(body).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityOAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityOAuthError.serverError("HTTP \(http.statusCode): \(body)")
        }
    }

    private func subscriptionTier(from json: [String: Any]) -> String? {
        if let paidTier = tierName(json["paidTier"]) {
            return paidTier
        }

        if let ineligibleTiers = json["ineligibleTiers"] as? [Any], !ineligibleTiers.isEmpty {
            if let allowedTiers = json["allowedTiers"] as? [[String: Any]],
               let fallback = allowedTiers.first(where: { ($0["isDefault"] as? Bool) == true }).flatMap(tierName) {
                return "\(fallback) (Restricted)"
            }
            return nil
        }

        return tierName(json["currentTier"])
    }

    private func tierName(_ value: Any?) -> String? {
        guard let tier = value as? [String: Any] else { return nil }
        if let name = tier["name"] as? String, !name.isEmpty {
            return name
        }
        if let id = tier["id"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    private func formEncoded(_ body: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        return body
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
    }

    static var nativeOAuthUserAgent: String {
        "vscode/1.X.X (Antigravity/4.1.32)"
    }
}

struct AntigravityOAuthTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var tokenType: String
    var refreshToken: String?
    var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

struct AntigravityGoogleUserInfo: Decodable {
    var email: String
    var name: String?
    var givenName: String?
    var familyName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case name
        case givenName = "given_name"
        case familyName = "family_name"
    }

    var displayName: String? {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        let parts = [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct AntigravityProjectMetadata {
    var projectId: String?
    var subscriptionTier: String?
}
