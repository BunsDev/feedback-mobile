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
        .onChange(of: method) { _, _ in
            isSending = false
            codeSent = false
            otp = ""
            isCreatingAccount = false
            auth.clearMessages()
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
                primaryButton("Send Code", disabled: emailEmpty || isSending) { await sendCode() }
            } else {
                primaryButton("Verify", disabled: otp.trimmed.isEmpty) { await verify() }
                Button("Resend Code") { otp = ""; codeSent = false }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                    .disabled(isSending)
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
