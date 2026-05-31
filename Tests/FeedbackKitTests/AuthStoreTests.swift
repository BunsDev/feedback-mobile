@testable import FeedbackKit
import XCTest

final class StubAuthService: AuthService, @unchecked Sendable {
    var sentTo: String?
    var tokenToReturn = "session_tok"
    var sendError: Error?
    func sendOTP(email: String) async throws {
        if let sendError { throw sendError }
        sentTo = email
    }
    func verifyOTP(email: String, code: String) async throws -> String { tokenToReturn }

    // Password auth knobs
    var passwordToken = "pw_tok"
    var signUpToken = "signup_tok"
    var passwordError: Error?
    var signUpError: Error?
    var resetError: Error?
    var resetRequestedFor: String?

    func signInWithPassword(email: String, password: String) async throws -> String {
        if let passwordError { throw passwordError }
        return passwordToken
    }
    func signUp(name: String, email: String, password: String) async throws -> String {
        if let signUpError { throw signUpError }
        return signUpToken
    }
    func requestPasswordReset(email: String) async throws {
        if let resetError { throw resetError }
        resetRequestedFor = email
    }
}

@MainActor
final class AuthStoreTests: XCTestCase {
    func testSignInStoresTokenAndFlipsState() async {
        let store = InMemoryTokenStore()
        let auth = AuthStore(service: StubAuthService(), tokenStore: store)
        XCTAssertFalse(auth.isSignedIn)
        try? await auth.requestCode(email: "v@x.com")
        await auth.verify(email: "v@x.com", code: "123456")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(store.token, "session_tok")
    }

    func testSignOutClearsToken() async {
        let store = InMemoryTokenStore(token: "old")
        let auth = AuthStore(service: StubAuthService(), tokenStore: store)
        XCTAssertTrue(auth.isSignedIn)
        auth.signOut()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(store.token)
    }

    func testRequestCodeFailureSetsErrorMessageAndRethrows() async {
        let service = StubAuthService()
        service.sendError = APIError.transport("offline")
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())

        do {
            try await auth.requestCode(email: "v@x.com")
            XCTFail("Expected requestCode to throw")
        } catch {
            XCTAssertEqual(auth.errorMessage, "Couldn't send a code. Please try again.")
        }
    }

    func testPasswordSignInStoresTokenAndFlipsState() async {
        let service = StubAuthService()
        service.passwordToken = "pw_tok"
        let store = InMemoryTokenStore()
        let auth = AuthStore(service: service, tokenStore: store)
        await auth.signInWithPassword(email: "v@x.com", password: "secret123")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(store.token, "pw_tok")
        XCTAssertNil(auth.errorMessage)
    }

    func testPasswordSignInBadCredentialsSetsSpecificError() async {
        let service = StubAuthService()
        service.passwordError = APIError.auth(code: "INVALID_EMAIL_OR_PASSWORD", message: "x")
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())
        await auth.signInWithPassword(email: "v@x.com", password: "bad")
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertEqual(auth.errorMessage, "Wrong email or password.")
    }

    func testSignUpStoresTokenAndFlipsState() async {
        let service = StubAuthService()
        service.signUpToken = "new_tok"
        let store = InMemoryTokenStore()
        let auth = AuthStore(service: service, tokenStore: store)
        await auth.signUp(name: "Ada", email: "ada@x.com", password: "secret123")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(store.token, "new_tok")
    }

    func testSignUpDuplicateEmailSetsSpecificError() async {
        let service = StubAuthService()
        service.signUpError = APIError.auth(code: "USER_ALREADY_EXISTS", message: "x")
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())
        await auth.signUp(name: "Ada", email: "ada@x.com", password: "secret123")
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertEqual(auth.errorMessage, "An account with this email already exists.")
    }

    func testRequestPasswordResetSetsInfoMessageAndDoesNotSignIn() async {
        let service = StubAuthService()
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())
        await auth.requestPasswordReset(email: "v@x.com")
        XCTAssertEqual(service.resetRequestedFor, "v@x.com")
        XCTAssertEqual(auth.infoMessage, "Check your email for a reset link.")
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.errorMessage)
    }

    func testRequestPasswordResetFailureSetsError() async {
        let service = StubAuthService()
        service.resetError = APIError.transport("offline")
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())
        await auth.requestPasswordReset(email: "v@x.com")
        XCTAssertNil(auth.infoMessage)
        XCTAssertEqual(auth.errorMessage, "Something went wrong. Please try again.")
    }

    func testClearMessagesResetsErrorAndInfo() async {
        let service = StubAuthService()
        service.passwordError = APIError.auth(code: "INVALID_EMAIL_OR_PASSWORD", message: "x")
        let auth = AuthStore(service: service, tokenStore: InMemoryTokenStore())
        await auth.signInWithPassword(email: "v@x.com", password: "bad")
        XCTAssertNotNil(auth.errorMessage)
        auth.clearMessages()
        XCTAssertNil(auth.errorMessage)
        XCTAssertNil(auth.infoMessage)
    }
}
