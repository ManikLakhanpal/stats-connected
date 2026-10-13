import SwiftUI
import UIKit

struct LoginView: View {
    @ObservedObject var auth = RemoteAuthService.shared
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Stats Fleet")
                .font(.title.bold())

            Text("Sign in with your System Stats account to see Macs that already stream from the Stats app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Label("Enable Remote monitoring on each Mac", systemImage: "checkmark.circle.fill")
                Label("Complete sign-in in Safari when prompted", systemImage: "checkmark.circle.fill")
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if let code = auth.loginUserCode {
                Text("User code: \(code)")
                    .font(.headline.monospaced())
                if auth.isPolling {
                    ProgressView("Waiting for authorization…")
                }
            }

            if let error = auth.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await startLogin() }
            } label: {
                if isStarting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(auth.loginUserCode == nil ? "Sign in" : "Open browser again")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStarting || auth.isPolling)

            if auth.loginUserCode != nil {
                Button("Cancel") {
                    auth.cancelLogin()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func startLogin() async {
        isStarting = true
        defer { isStarting = false }
        do {
            let url = try await auth.startLogin()
            await UIApplication.shared.open(url)
        } catch {
            auth.lastError = error.localizedDescription
        }
    }
}
