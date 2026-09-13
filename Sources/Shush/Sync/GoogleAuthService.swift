import AppKit
import CryptoKit
import Foundation

/// Google sign-in via a hand-rolled OAuth2 PKCE flow — no Google SDK dependency, matching this
/// codebase's "minimal deps, hand-roll it" ethos (FluidAudio is the only third-party package,
/// and it's there for models no hand-rolled code could replace).
///
/// Scope is `drive.appdata` (a private, per-app Drive folder invisible in the user's normal
/// Drive UI) plus `openid email`, requested purely to show which account is connected — no
/// extra Drive access comes with it.
///
/// The redirect is a local loopback HTTP listener (RFC 8252), not `shush://` — Google's OAuth
/// validation for a "Desktop app" client type only recognizes `http://127.0.0.1:<port>/...`
/// redirects; a custom URL scheme gets rejected with "Error 400: invalid_request" even though
/// it's registered in Info.plist, since that registration governs macOS routing, not Google's
/// own allow-list. See `LoopbackRedirectServer`.
@MainActor
@Observable
final class GoogleAuthService {
    static let shared = GoogleAuthService()

    private static let clientID = "97943787374-oaffa7jrpnank77o404ip9tbkhp9er63.apps.googleusercontent.com"
    private static let scope = "https://www.googleapis.com/auth/drive.appdata openid email"
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private static let userInfoEndpoint = "https://www.googleapis.com/oauth2/v3/userinfo"
    private static let revokeEndpoint = "https://oauth2.googleapis.com/revoke"

    private static let keychainService = "ai.pivotstudio.shush.googleAuth"
    private static let keychainAccount = "tokens"

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private var tokens: Tokens?

    var isSignedIn: Bool { tokens != nil }

    private init() {
        if let data = KeychainStore.load(service: Self.keychainService, account: Self.keychainAccount),
           let decoded = try? JSONDecoder().decode(Tokens.self, from: data) {
            tokens = decoded
        }
    }

    // MARK: - Sign in / out

    func signIn() async throws {
        let verifier = Self.randomURLSafeString(byteCount: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 16)

        let (port, socketFD) = try LoopbackRedirectServer.start()
        let redirectURI = "http://127.0.0.1:\(port)/oauth-callback"

        var components = URLComponents(string: Self.authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Without this, Google only issues a refresh token on the very first consent —
            // any later re-auth (e.g. after a revoke) would silently come back access-token-only.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard NSWorkspace.shared.open(components.url!) else { throw SyncError.oauthCallbackInvalid }

        let query = await LoopbackRedirectServer.awaitRedirect(socketFD: socketFD)
        guard query["state"] == state, let code = query["code"] else {
            throw SyncError.oauthCallbackInvalid
        }

        try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        try await refreshEmail()
    }

    /// Best-effort revoke, then clears everything local regardless of whether the network call
    /// succeeds — a user asking to disconnect should never be stuck signed in because Google's
    /// revoke endpoint timed out. Local Settings/Dictionary/Stats are untouched: sign-out isn't
    /// destructive, it just stops syncing.
    func disconnect() async {
        if let accessToken = tokens?.accessToken {
            var request = URLRequest(url: URL(string: "\(Self.revokeEndpoint)?token=\(accessToken)")!)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
        clearLocalState()
    }

    private func clearLocalState() {
        tokens = nil
        KeychainStore.delete(service: Self.keychainService, account: Self.keychainAccount)
        Settings.shared.googleAccountEmail = nil
    }

    // MARK: - Access token

    /// Refreshes proactively when close to expiry, so callers never see a 401 from an expired
    /// token — `DriveClient` can assume this always returns a usable token or throws.
    func validAccessToken() async throws -> String {
        guard var current = tokens else { throw SyncError.notSignedIn }
        if current.expiresAt <= Date().addingTimeInterval(60) {
            current = try await refresh(current)
        }
        return current.accessToken
    }

    private func refresh(_ current: Tokens) async throws -> Tokens {
        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
            "client_id": Self.clientID,
            "client_secret": GoogleOAuthSecret.value,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // The refresh token itself is dead (revoked externally, expired) — don't keep
            // retrying against it every sync cycle. Sign out and let the user reconnect.
            clearLocalState()
            throw SyncError.tokenExpired
        }

        struct RefreshResponse: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)

        let updated = Tokens(
            accessToken: decoded.access_token,
            // Google doesn't always return a new refresh token on refresh — keep the old one.
            refreshToken: decoded.refresh_token ?? current.refreshToken,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        )
        store(updated)
        return updated
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "authorization_code",
            "code": code,
            // Must match the exact redirect_uri used in the authorization request, including
            // the ephemeral port — token exchange fails otherwise.
            "redirect_uri": redirectURI,
            "client_id": Self.clientID,
            "client_secret": GoogleOAuthSecret.value,
            "code_verifier": verifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SyncError.driveAPI(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "token exchange failed")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        store(Tokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        ))
    }

    private func refreshEmail() async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: Self.userInfoEndpoint)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

        struct UserInfo: Decodable { let email: String? }
        if let email = try? JSONDecoder().decode(UserInfo.self, from: data).email {
            Settings.shared.googleAccountEmail = email
        }
    }

    private func store(_ tokens: Tokens) {
        self.tokens = tokens
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        KeychainStore.save(data, service: Self.keychainService, account: Self.keychainAccount)
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Internal (not private) so it's directly unit-testable against fixed verifiers. Pure
    /// function, no actor-isolated state — `nonisolated` so tests can call it synchronously.
    nonisolated static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formBody(_ params: [String: String]) -> Data {
        params.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encodedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)!
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
