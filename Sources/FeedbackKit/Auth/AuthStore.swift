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

    private let service: AuthService
    private let tokenStore: TokenStore

    public init(service: AuthService, tokenStore: TokenStore) {
        self.service = service
        self.tokenStore = tokenStore
        self.isSignedIn = tokenStore.token != nil
    }

    public var token: String? { tokenStore.token }

    public func requestCode(email: String) async throws {
        errorMessage = nil
        do {
            try await service.sendOTP(email: email)
        } catch {
            errorMessage = "Couldn't send a code. Please try again."
            throw error
        }
    }

    public func verify(email: String, code: String) async {
        errorMessage = nil
        do {
            let token = try await service.verifyOTP(email: email, code: code)
            tokenStore.token = token
            isSignedIn = true
        } catch {
            errorMessage = "That code didn't work. Try again."
            isSignedIn = false
        }
    }

    public func signOut() {
        tokenStore.token = nil
        isSignedIn = false
    }
}
