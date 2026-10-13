import SwiftUI

struct RootView: View {
    @ObservedObject private var auth = RemoteAuthService.shared
    @State private var didRestore = false

    var body: some View {
        Group {
            if auth.isAuthorized {
                FleetView()
            } else if !didRestore {
                ProgressView("Restoring session…")
            } else {
                LoginView()
            }
        }
        .task {
            await auth.restoreSession()
            didRestore = true
        }
    }
}
