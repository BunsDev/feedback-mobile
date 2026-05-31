import Foundation

// NOTE: Endpoint paths follow the better-auth convention and are verified against
// a live instance (feedback.opencoven.ai). AuthService/AuthStore interfaces are stable.
public final class HTTPAuthService: AuthService, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    public init(baseURL: URL, session: URLSession = .shared) { self.baseURL = baseURL; self.session = session }

    public func sendOTP(email: String) async throws {
        _ = try await post("/api/auth/email-otp/send-verification-otp", body: ["email": email, "type": "sign-in"])
    }

    public func verifyOTP(email: String, code: String) async throws -> String {
        let data = try await post("/api/auth/sign-in/email-otp", body: ["email": email, "otp": code])
        return try Self.token(from: data)
    }

    public func signInWithPassword(email: String, password: String) async throws -> String {
        let data = try await post("/api/auth/sign-in/email", body: ["email": email, "password": password])
        return try Self.token(from: data)
    }

    public func signUp(name: String, email: String, password: String) async throws -> String {
        let data = try await post("/api/auth/sign-up/email", body: ["name": name, "email": email, "password": password])
        return try Self.token(from: data)
    }

    public func requestPasswordReset(email: String) async throws {
        // better-auth requires redirectTo; reset is completed on the web, not in-app.
        _ = try await post("/api/auth/request-password-reset", body: ["email": email, "redirectTo": "/"])
    }

    // MARK: - Helpers

    private static func token(from data: Data) throws -> String {
        do {
            return try JSONDecoder().decode(SignInResponse.self, from: data).token
        } catch {
            throw APIError.decoding("No token in sign-in response: \(error.localizedDescription)")
        }
    }

    private struct SignInResponse: Decodable {
        let token: String
    }

    private struct AuthErrorBody: Decodable {
        let message: String?
        let code: String?
    }

    private func post(_ path: String, body: [String: String]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(AuthErrorBody.self, from: data),
               err.code != nil || err.message != nil {
                throw APIError.auth(code: err.code, message: err.message)
            }
            throw APIError.server(status: http.statusCode, code: nil)
        }
        return data
    }
}
