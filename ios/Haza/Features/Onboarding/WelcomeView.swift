import SwiftUI
import AuthenticationServices
import CryptoKit
import HazaCore

struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @State private var email = ""
    @State private var inviteCode = ""
    @State private var sentMagicLink = false
    @State private var code = ""
    @State private var checking = false
    @State private var nonce = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Eyebrow("For people who drive together")
            Headline("See your friends on the road. Talk with one press.", size: 38)
            Text("Live map, walkie-talkie on iPhone, Apple Watch and CarPlay, drives you plan together, and your radar detector on the same screen.")
                .font(.system(size: 15)).foregroundStyle(HazaTheme.muted).lineSpacing(3)

            // Sign in with Apple needs the applesignin entitlement — absent in a free-Apple-ID build,
            // where the button would only fail with error 1000. Email is the universal path.
            if Entitlements.signInWithApple {
                SignInWithAppleButton(.signIn) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                } onCompletion: { result in
                    guard case .success(let auth) = result,
                          let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = cred.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { return }
                    let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                    Task { await state.signInWithApple(idToken: idToken, nonce: nonce, fullName: name.isEmpty ? nil : name) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 8) {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 14).frame(height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                Button(sentMagicLink ? "Resend" : "Continue") { Task { await state.signInWithEmail(email.trimmingCharacters(in: .whitespaces)); sentMagicLink = true } }
                    .font(.system(size: 15, weight: .semibold)).frame(width: 92, height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                    .disabled(!email.contains("@"))
            }

            if sentMagicLink {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Check your email. Tap the link, or type the 6-digit code here. (No code in the email? Long-press the link, Copy Link, and paste it here.)")
                        .font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                    HStack(spacing: 8) {
                        TextField("000000", text: $code).keyboardType(.default).textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 14).frame(height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                            .onChange(of: code) { _, v in
                                if !v.contains("token=") {
                                    code = String(v.filter(\.isNumber).prefix(6))
                                    if code.count == 6 { Task { await verify() } }
                                } else { Task { await verify() } }
                            }
                        Button(checking ? "…" : "Sign in") { Task { await verify() } }
                            .font(.system(size: 15, weight: .semibold)).frame(width: 92, height: 50)
                            .background(HazaTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(HazaTheme.bg)
                            .disabled(!(code.count == 6 || code.contains("token=")) || checking)
                    }
                }
            }
            if let err = state.lastError { Text(err).font(.system(size: 12)).foregroundStyle(HazaTheme.alert) }

            HStack(spacing: 6) {
                Text("Have an invite code?").font(.system(size: 13)).foregroundStyle(HazaTheme.muted)
                TextField("XXXX-XXXX", text: $inviteCode).font(.system(size: 13, weight: .semibold)).textInputAutocapitalization(.characters)
                    .onChange(of: inviteCode) { _, v in state.pendingInviteCode = Referral.normalize(v) }
                Button("Paste") {
                    if let s = UIPasteboard.general.string, let c = Referral.code(fromPasteboard: s) { inviteCode = Referral.display(c); state.pendingInviteCode = c }
                }.font(.system(size: 13, weight: .semibold))
            }
            if let code = state.pendingInviteCode {
                Text("Code \(Referral.display(code)) will be applied after you sign in.").font(.system(size: 12)).foregroundStyle(HazaTheme.muted)
            }
        }
        .padding(24)
        .foregroundStyle(HazaTheme.ink)
    }

    private func verify() async {
        guard code.count == 6 || code.contains("token="), !checking else { return }
        checking = true
        _ = await state.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: code)
        checking = false
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}

/// Shown once after the first sign-in. Email sign-ins arrive nameless; Apple sign-ins arrive with one.
struct NameView: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Eyebrow("One thing first")
            Headline("What should friends call you?", size: 34)
            Text("This is the name on your car chip and in the walkie-talkie. You can change it later in Profile.")
                .font(.system(size: 15)).foregroundStyle(HazaTheme.muted)
            TextField("Your name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                .font(HazaTheme.display(24)).padding(.horizontal, 14).frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HazaTheme.hair, lineWidth: 1))
                .submitLabel(.done).onSubmit { Task { await save() } }
            PrimaryButton(title: saving ? "Saving…" : "Continue") { Task { await save() } }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            Spacer()
        }
        .padding(24)
        .foregroundStyle(HazaTheme.ink)
        .task { name = state.profile?.displayName ?? "" }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        await state.confirmName(name)
        saving = false
    }
}
