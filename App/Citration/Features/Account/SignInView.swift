import AuthenticationServices
import CitrationCore
import SwiftUI

struct SignInView: View {
    // MARK: Internal

    let onSignIn: (String) async throws -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Citration")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Sign in to sync your library across devices")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(width: 280, height: 44)
            .disabled(isSigningIn)

            if isSigningIn {
                ProgressView("Signing in...")
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Spacer()

            Button("Continue without account") {
                // Allow offline/local-only usage
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private func handleSignInResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                errorMessage = "Failed to get identity token from Apple"
                return
            }

            isSigningIn = true
            errorMessage = nil

            Task {
                do {
                    try await onSignIn(identityToken)
                } catch {
                    isSigningIn = false
                    errorMessage = error.localizedDescription
                }
            }

        case let .failure(error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
