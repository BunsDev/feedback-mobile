# Password Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email+password sign-in, account creation, and password-reset-request to FeedbackPortalApp alongside the existing email-OTP flow.

**Architecture:** Extend the existing `AuthService` (protocol) → `AuthStore` (state) → `SignInSheet` (view) seam. `HTTPAuthService` calls better-auth's `/api/auth/sign-in/email`, `/api/auth/sign-up/email`, and `/api/auth/request-password-reset`. Both sign-in and sign-up return a session token (backend `autoSignIn: true`), stored identically to the OTP token, so the existing `needsSignIn`/pending-action replay machinery works unchanged. Password reset is completed on the web (emailed link); the app only triggers the email.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, Swift Package Manager. Tests run via `swift test` (FeedbackKit, no simulator). Spec: `docs/superpowers/specs/2026-05-31-password-auth-design.md`.

---

## File Structure

- **Modify** `Sources/FeedbackKit/API/APIError.swift` — add `.auth(code:message:)` case.
- **Modify** `Sources/FeedbackKit/Auth/AuthStore.swift` — add 3 methods to the `AuthService` protocol; add `infoMessage` + 3 methods + a shared message-mapping helper to `AuthStore`.
- **Modify** `Sources/FeedbackKit/Auth/HTTPAuthService.swift` — implement the 3 methods; upgrade the private `post` helper to decode better-auth's `{message, code}` error body; extract a shared `token(from:)` helper.
- **Modify** `Tests/FeedbackKitTests/HTTPAuthServiceTests.swift` — tests for the 3 network methods + error decoding.
- **Modify** `Tests/FeedbackKitTests/AuthStoreTests.swift` — extend `StubAuthService` with the 3 methods + control knobs; add `AuthStore` behavior tests.
- **Modify** `App/FeedbackPortalApp/SignInSheet.swift` — segmented "Email Code | Password" picker; password sign-in / create-account / forgot-password UI.

---

## Task 1: Add `APIError.auth` case

**Files:**
- Modify: `Sources/FeedbackKit/API/APIError.swift`

- [ ] **Step 1: Add the case**

Replace the enum body in `Sources/FeedbackKit/API/APIError.swift` with:

```swift
import Foundation

public enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case notFound
    case rateLimited
    case server(status: Int, code: String?)
    case transport(String)
    case decoding(String)
    case auth(code: String?, message: String?)
}
```

- [ ] **Step 2: Verify the package builds**

Run: `swift build`
Expected: `Build complete!` (no errors; `Equatable` auto-derives for the new case).

- [ ] **Step 3: Commit**

```bash
git add Sources/FeedbackKit/API/APIError.swift
git commit -m "feat(auth): add APIError.auth case for better-auth error bodies"
```

---

## Task 2: Service layer — protocol + HTTPAuthService + StubAuthService

Adding methods to the `AuthService` protocol forces every conformer to implement them, so the protocol, the real `HTTPAuthService`, and the test-double `StubAuthService` are done together to keep the package compiling. TDD drives the `HTTPAuthService` network behavior.

**Files:**
- Modify: `Sources/FeedbackKit/Auth/AuthStore.swift` (protocol only)
- Modify: `Sources/FeedbackKit/Auth/HTTPAuthService.swift`
- Modify: `Tests/FeedbackKitTests/HTTPAuthServiceTests.swift`
- Modify: `Tests/FeedbackKitTests/AuthStoreTests.swift` (StubAuthService only)

- [ ] **Step 1: Add the 3 methods to the `AuthService` protocol**

In `Sources/FeedbackKit/Auth/AuthStore.swift`, replace the protocol declaration with:

```swift
public protocol AuthService: Sendable {
    func sendOTP(email: String) async throws
    func verifyOTP(email: String, code: String) async throws -> String  // returns session token
    func signInWithPassword(email: String, password: String) async throws -> String  // session token
    func signUp(name: String, email: String, password: String) async throws -> String // session token
    func requestPasswordReset(email: String) async throws
}
```

- [ ] **Step 2: Write failing tests for the 3 HTTPAuthService methods**

In `Tests/FeedbackKitTests/HTTPAuthServiceTests.swift`, add these methods inside `HTTPAuthServiceTests` (after `testVerifyReturnsToken`):

```swift
    func testSignInWithPasswordPostsCredentialsAndReturnsToken() async throws {
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/auth/sign-in/email")
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter HTTPAuthServiceTests`
Expected: FAIL — compile errors, `value of type 'HTTPAuthService' has no member 'signInWithPassword'` (and the others).

- [ ] **Step 4: Implement the 3 methods + upgrade `post` + share token extraction**

Replace the entire body of `Sources/FeedbackKit/Auth/HTTPAuthService.swift` with:

```swift
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
        _ = try await post("/api/auth/request-password-reset", body: ["email": email, "redirectTo": "/"])
    }

    // MARK: - Helpers

    private static func token(from data: Data) throws -> String {
        struct SignInResponse: Decodable { let token: String }
        guard let token = try? JSONDecoder().decode(SignInResponse.self, from: data).token else {
            throw APIError.decoding("No token in sign-in response")
        }
        return token
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
```

- [ ] **Step 5: Add the 3 methods to `StubAuthService` so the test target compiles**

In `Tests/FeedbackKitTests/AuthStoreTests.swift`, replace the `StubAuthService` declaration with:

```swift
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
    var passwordToken = "session_tok"
    var signUpToken = "session_tok"
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
```

Note: `FailingAuthService` (defined later in the same file) also conforms to `AuthService`. If the build reports it is missing the new methods, add minimal throwing/no-op implementations to it:

```swift
    func signInWithPassword(email: String, password: String) async throws -> String { throw OTPError() }
    func signUp(name: String, email: String, password: String) async throws -> String { throw OTPError() }
    func requestPasswordReset(email: String) async throws { throw OTPError() }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter HTTPAuthServiceTests`
Expected: PASS — all 5 tests (1 existing + 4 new).

- [ ] **Step 7: Run the full suite to confirm nothing broke**

Run: `swift test`
Expected: PASS — the existing baseline tests (85 on this branch) still green (the new protocol methods are implemented by both conformers).

- [ ] **Step 8: Commit**

```bash
git add Sources/FeedbackKit/Auth/HTTPAuthService.swift Sources/FeedbackKit/Auth/AuthStore.swift Tests/FeedbackKitTests/HTTPAuthServiceTests.swift Tests/FeedbackKitTests/AuthStoreTests.swift
git commit -m "feat(auth): HTTPAuthService password sign-in/up + reset request"
```

---

## Task 3: `AuthStore.signInWithPassword` + shared message mapping

**Files:**
- Modify: `Sources/FeedbackKit/Auth/AuthStore.swift`
- Modify: `Tests/FeedbackKitTests/AuthStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/FeedbackKitTests/AuthStoreTests.swift`, add inside `AuthStoreTests`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AuthStoreTests`
Expected: FAIL — `value of type 'AuthStore' has no member 'signInWithPassword'`.

- [ ] **Step 3: Implement `signInWithPassword` + `authMessage` helper**

In `Sources/FeedbackKit/Auth/AuthStore.swift`, add inside `AuthStore` (after the `verify` method):

```swift
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
```

Also add the `infoMessage` published property next to `errorMessage` near the top of `AuthStore`:

```swift
    @Published public private(set) var infoMessage: String?
```

Finally, so a stale reset confirmation does not linger when the user switches to another flow, clear `infoMessage` at the start of the two existing OTP methods. In `requestCode(email:)` change the first line `errorMessage = nil` to:

```swift
        errorMessage = nil; infoMessage = nil
```

and in `verify(email:code:)` change its first line `errorMessage = nil` to:

```swift
        errorMessage = nil; infoMessage = nil
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AuthStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeedbackKit/Auth/AuthStore.swift Tests/FeedbackKitTests/AuthStoreTests.swift
git commit -m "feat(auth): AuthStore password sign-in with friendly error mapping"
```

---

## Task 4: `AuthStore.signUp`

**Files:**
- Modify: `Sources/FeedbackKit/Auth/AuthStore.swift`
- Modify: `Tests/FeedbackKitTests/AuthStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/FeedbackKitTests/AuthStoreTests.swift`, add inside `AuthStoreTests`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AuthStoreTests`
Expected: FAIL — `value of type 'AuthStore' has no member 'signUp'`.

- [ ] **Step 3: Implement `signUp`**

In `Sources/FeedbackKit/Auth/AuthStore.swift`, add inside `AuthStore` (after `signInWithPassword`):

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AuthStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeedbackKit/Auth/AuthStore.swift Tests/FeedbackKitTests/AuthStoreTests.swift
git commit -m "feat(auth): AuthStore account creation (signUp)"
```

---

## Task 5: `AuthStore.requestPasswordReset` + `infoMessage`

**Files:**
- Modify: `Sources/FeedbackKit/Auth/AuthStore.swift`
- Modify: `Tests/FeedbackKitTests/AuthStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/FeedbackKitTests/AuthStoreTests.swift`, add inside `AuthStoreTests`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AuthStoreTests`
Expected: FAIL — `value of type 'AuthStore' has no member 'requestPasswordReset'`.

- [ ] **Step 3: Implement `requestPasswordReset`**

In `Sources/FeedbackKit/Auth/AuthStore.swift`, add inside `AuthStore` (after `signUp`):

```swift
    public func requestPasswordReset(email: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            try await service.requestPasswordReset(email: email)
            infoMessage = "Check your email for a reset link."
        } catch {
            errorMessage = Self.authMessage(for: error)
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter AuthStoreTests`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — all auth + existing tests green.

- [ ] **Step 6: Commit**

```bash
git add Sources/FeedbackKit/Auth/AuthStore.swift Tests/FeedbackKitTests/AuthStoreTests.swift
git commit -m "feat(auth): AuthStore password reset request with infoMessage"
```

---

## Task 6: `SignInSheet` — segmented Email Code | Password UI

This is a SwiftUI view; it is verified by building the app and a manual smoke test (Task 7), not by unit tests. The full file is replaced because the body is restructured around a method picker.

**Files:**
- Modify: `App/FeedbackPortalApp/SignInSheet.swift`

- [ ] **Step 1: Replace the file**

Replace the entire contents of `App/FeedbackPortalApp/SignInSheet.swift` with:

```swift
import FeedbackKit
import SwiftUI

struct SignInSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private enum Method: String, CaseIterable {
        case code = "Email Code"
        case password = "Password"
    }

    @State private var method: Method = .code

    // Shared
    @State private var email = ""
    @State private var isSending = false

    // OTP
    @State private var otp = ""
    @State private var codeSent = false

    // Password
    @State private var password = ""
    @State private var name = ""
    @State private var isCreatingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $method) {
                        ForEach(Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch method {
                case .code: otpSection
                case .password: passwordSection
                }

                if let error = auth.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.subheadline) }
                }
                if let info = auth.infoMessage {
                    Section { Text(info).foregroundStyle(.secondary).font(.subheadline) }
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            if isSignedIn { dismiss() }
        }
    }

    // MARK: - OTP

    @ViewBuilder private var otpSection: some View {
        Section {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .disabled(codeSent)
        }

        if codeSent {
            Section {
                TextField("6-digit code", text: $otp)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }
        }

        Section {
            if !codeSent {
                primaryButton("Send Code", disabled: emailEmpty) { await sendCode() }
            } else {
                primaryButton("Verify", disabled: otp.trimmed.isEmpty) { await verify() }
                Button("Resend Code") { otp = ""; codeSent = false }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Password

    @ViewBuilder private var passwordSection: some View {
        Section {
            if isCreatingAccount {
                TextField("Name", text: $name)
                    .textContentType(.name)
            }
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            SecureField("Password (min 8 characters)", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
        }

        Section {
            if isCreatingAccount {
                primaryButton("Create Account", disabled: !canSubmitPassword || name.trimmed.isEmpty) { await signUp() }
            } else {
                primaryButton("Sign In", disabled: !canSubmitPassword) { await signInWithPassword() }
            }

            Button(isCreatingAccount ? "Have an account? Sign in" : "Create an account") {
                isCreatingAccount.toggle()
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)

            if !isCreatingAccount {
                Button("Forgot password?") { Task { await requestReset() } }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                    .disabled(emailEmpty || isSending)
            }
        }
    }

    // MARK: - Helpers

    private var emailEmpty: Bool { email.trimmed.isEmpty }
    private var canSubmitPassword: Bool { !emailEmpty && password.count >= 8 && !isSending }

    @ViewBuilder
    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isSending {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .disabled(disabled)
    }

    private func sendCode() async {
        isSending = true
        do { try await auth.requestCode(email: email); codeSent = true } catch {}
        isSending = false
    }

    private func verify() async {
        isSending = true
        await auth.verify(email: email, code: otp)
        isSending = false
    }

    private func signInWithPassword() async {
        isSending = true
        await auth.signInWithPassword(email: email, password: password)
        isSending = false
    }

    private func signUp() async {
        isSending = true
        await auth.signUp(name: name, email: email, password: password)
        isSending = false
    }

    private func requestReset() async {
        isSending = true
        await auth.requestPasswordReset(email: email)
        isSending = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
```

- [ ] **Step 2: Build the app for the simulator**

Run:
```bash
xcodegen generate
xcodebuild -project FeedbackApp.xcodeproj -scheme FeedbackPortalApp \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath .build/dd build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head
```
Expected: `BUILD SUCCEEDED` (compilation only; ignore CodeSign in Release — this is a Debug build).

- [ ] **Step 3: Run the full test suite**

Run: `swift test`
Expected: PASS — all FeedbackKit tests still green (UI change does not affect them).

- [ ] **Step 4: Commit**

```bash
git add App/FeedbackPortalApp/SignInSheet.swift
git commit -m "feat(app): segmented Email Code | Password sign-in sheet"
```

---

## Task 7: Manual verification (simulator, against live)

Unit tests cover the logic; this task confirms the real flows. Requires a real inbox for OTP/reset emails. Performed interactively with the user.

**Files:** none (verification only)

- [ ] **Step 1: Build + install against the live instance**

Create the gitignored opt-in config so the app points at the live instance:
```bash
printf 'FEEDBACK_INSTANCE_URL = https:/$()/feedback.opencoven.ai\n' > FeedbackApp/FeedbackApp.xcconfig
xcodegen generate
DEV=$(xcrun simctl list devices "iOS 26.5" available | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl boot "$DEV" 2>/dev/null; open -a Simulator
xcodebuild -project FeedbackApp.xcodeproj -scheme FeedbackPortalApp \
  -destination "platform=iOS Simulator,id=$DEV" -configuration Release \
  -derivedDataPath .build/live clean build 2>&1 | grep -E "BUILD SUCCEEDED|error:" | head
APP=.build/live/Build/Products/Release-iphonesimulator/FeedbackPortalApp.app
xattr -cr "$APP"; codesign --force --deep --sign - "$APP"
xcrun simctl install "$DEV" "$APP"; xcrun simctl launch "$DEV" dev.opencoven.feedbackportal
```
Expected: `BUILD SUCCEEDED`; app launches.

- [ ] **Step 2: Verify the three flows with the user**

On the Account tab → Sign In, confirm with the user:
1. **Password sign-in:** pick "Password", enter a known account's email + password → "Signed in".
2. **Account creation:** "Create an account", enter name + a fresh email + password ≥ 8 → "Signed in".
3. **Forgot password:** in password mode, enter an email → "Forgot password?" → "Check your email for a reset link." appears.

Expected: each behaves as described; wrong password shows "Wrong email or password."

- [ ] **Step 3: Clean up the local opt-in config**

Run: `rm -f FeedbackApp/FeedbackApp.xcconfig && xcodegen generate`
Expected: app reverts to the localhost default for local dev.

---

## Notes

- The plan does not modify `project.yml`'s `FEEDBACK_INSTANCE_URL` wiring — that is already set up (localhost default + gitignored xcconfig opt-in).
- `xcodegen generate` regenerates the gitignored `.xcodeproj`; it is not committed.
- Password reset email delivery depends on the live instance's SMTP/Resend config and cannot be guaranteed by this change (see spec caveat).
