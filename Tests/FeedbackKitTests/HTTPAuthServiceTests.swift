@testable import FeedbackKit
import XCTest

final class HTTPAuthServiceTests: XCTestCase {
    private func make() -> HTTPAuthService {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return HTTPAuthService(baseURL: URL(string: "https://fb.example.com")!, session: URLSession(configuration: cfg))
    }
    func testVerifyReturnsToken() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/auth/sign-in/email-otp")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"token":"sess_123","user":{"id":"u1"}}"#.utf8))
        }
        let token = try await make().verifyOTP(email: "v@x.com", code: "123456")
        XCTAssertEqual(token, "sess_123")
    }

    func testSignInWithPasswordPostsCredentialsAndReturnsToken() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/auth/sign-in/email")
            // NOTE: URLSession delivers the body via httpBodyStream to URLProtocol; path assertion covers routing.
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"token":"sess_pw","user":{"id":"u1"}}"#.utf8))
        }
        let token = try await make().signInWithPassword(email: "v@x.com", password: "secret123")
        XCTAssertEqual(token, "sess_pw")
    }

    func testSignInWithPasswordMapsErrorBodyToAuthError() async {
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"message":"Invalid email or password","code":"INVALID_EMAIL_OR_PASSWORD"}"#.utf8))
        }
        do {
            _ = try await make().signInWithPassword(email: "v@x.com", password: "bad")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? APIError, .auth(code: "INVALID_EMAIL_OR_PASSWORD", message: "Invalid email or password"))
        }
    }

    func testSignUpPostsNameEmailPasswordAndReturnsToken() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/auth/sign-up/email")
            // NOTE: URLSession delivers the body via httpBodyStream to URLProtocol; path assertion covers routing.
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"token":"sess_new","user":{"id":"u2"}}"#.utf8))
        }
        let token = try await make().signUp(name: "Ada", email: "ada@x.com", password: "secret123")
        XCTAssertEqual(token, "sess_new")
    }

    func testRequestPasswordResetPostsToResetEndpoint() async throws {
        var seenPath: String?
        StubURLProtocol.handler = { req in
            seenPath = req.url?.path
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await make().requestPasswordReset(email: "v@x.com")
        XCTAssertEqual(seenPath, "/api/auth/request-password-reset")
    }
}
