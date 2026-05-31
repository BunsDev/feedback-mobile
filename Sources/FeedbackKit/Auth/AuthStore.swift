import Foundation

public protocol AuthService: Sendable {
    func sendOTP(email: String) async throws
    func verifyOTP(email: String, code: String) async throws -> String  // returns session token
    func signInWithPassword(email: String, password: String) async throws -> String  // session token
    func signUp(name: String, email: String, password: String) async throws -> String // session token
    func requestPasswordReset(email: String) async throws
}

@MainActor
public final class AuthStore: ObservableObject {
    @Published public private(set) var isSignedIn: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var infoMessage: String?

    private let service: AuthService
    private let tokenStore: TokenStore

    public init(service: AuthService, tokenStore: TokenStore) {
        self.service = service
        self.tokenStore = tokenStore
        self.isSignedIn = tokenStore.token != nil
    }

    public var token: String? { tokenStore.token }

    public func requestCode(email: String) async throws {
        errorMessage = nil; infoMessage = nil
        do {
            try await service.sendOTP(email: email)
        } catch {
            errorMessage = "Couldn't send a code. Please try again."
            throw error
        }
    }

    public func verify(email: String, code: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            let token = try await service.verifyOTP(email: email, code: code)
            tokenStore.token = token
            isSignedIn = true
        } catch {
            errorMessage = "That code didn't work. Try again."
            isSignedIn = false
        }
    }

    public func signInWithPassword(email: String, password: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            let token = try await service.signInWithPassword(email: email, password: password)
            tokenStore.token = token
            isSignedIn = true
        } catch {
            errorMessage = Self.authMessage(for: error)
            isSignedIn = false
        }
    }

    public func signUp(name: String, email: String, password: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            let token = try await service.signUp(name: name, email: email, password: password)
            tokenStore.token = token
            isSignedIn = true
        } catch {
            errorMessage = Self.authMessage(for: error)
            isSignedIn = false
        }
    }

    public func requestPasswordReset(email: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            try await service.requestPasswordReset(email: email)
            infoMessage = "Check your email for a reset link."
        } catch {
            errorMessage = Self.authMessage(for: error)
        }
    }

    static func authMessage(for error: Error) -> String {
        if case let APIError.auth(code, _) = error {
            switch code {
            case "INVALID_EMAIL_OR_PASSWORD": return "Wrong email or password."
            case "USER_ALREADY_EXISTS": return "An account with this email already exists."
            case "VALIDATION_ERROR": return "Password must be at least 8 characters."
            default: break
            }
        }
        return "Something went wrong. Please try again."
    }

    public func signOut() {
        tokenStore.token = nil
        isSignedIn = false
    }
}
