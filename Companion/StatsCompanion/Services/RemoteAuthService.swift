import Foundation

enum RemoteAuthError: Error {
    case unauthorized
    case deviceRegistrationFailed
    case loginCancelled
}

@MainActor
final class RemoteAuthService: ObservableObject {
    static let shared = RemoteAuthService()

    @Published private(set) var isAuthorized = false
    @Published private(set) var loginUserCode: String?
    @Published private(set) var isPolling = false
    @Published var lastError: String?

    private var credentialGeneration: UInt = 0
    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<String, Error>] = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private static let formAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private init() {
        isAuthorized = hasCredentials()
    }

    func hasCredentials() -> Bool {
        let access = KeychainStore.read("access_token") ?? ""
        let refresh = KeychainStore.read("refresh_token") ?? ""
        return !access.isEmpty && !refresh.isEmpty
    }

    func restoreSession() async {
        guard hasCredentials() else {
            isAuthorized = false
            return
        }
        do {
            _ = try await authorize()
            isAuthorized = true
        } catch RemoteAuthError.unauthorized {
            logout()
        } catch {
            isAuthorized = hasCredentials()
        }
    }

    func logout() {
        pollTask?.cancel()
        pollTask = nil
        credentialGeneration &+= 1
        KeychainStore.clearCredentials()
        isAuthorized = false
        loginUserCode = nil
        isPolling = false
        failRefreshWaiters(CancellationError())
    }

    func startLogin() async throws -> URL {
        lastError = nil
        pollTask?.cancel()

        let device = try await registerDevice()
        loginUserCode = device.user_code
        let interval = max(device.interval ?? 5, 2)

        pollTask = Task { [weak self] in
            await self?.pollForToken(deviceCode: device.device_code, interval: interval)
        }

        return device.verification_uri_complete
    }

    func cancelLogin() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        loginUserCode = nil
    }

    func authorize(rejectedToken: String? = nil) async throws -> String {
        let access = KeychainStore.read("access_token") ?? ""
        let refresh = KeychainStore.read("refresh_token") ?? ""
        guard !access.isEmpty, !refresh.isEmpty else {
            throw RemoteAuthError.unauthorized
        }
        if rejectedToken != access, !isTokenExpired(access) {
            return access
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                refreshWaiters.append(continuation)
            }
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let refresh = KeychainStore.read("refresh_token") ?? ""
        var request = URLRequest(url: APIConfig.authHost.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh),
            ("device_id", KeychainStore.deviceID),
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            completeRefreshWaiters(.failure(RemoteAuthError.unauthorized))
            throw RemoteAuthError.unauthorized
        }
        guard http.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !token.access_token.isEmpty,
              !token.refresh_token.isEmpty else {
            throw URLError(.badServerResponse)
        }

        KeychainStore.write(token.access_token, for: "access_token")
        KeychainStore.write(token.refresh_token, for: "refresh_token")
        completeRefreshWaiters(.success(token.access_token))
        return token.access_token
    }

    private func completeRefreshWaiters(_ result: Result<String, Error>) {
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        waiters.forEach { $0.resume(with: result) }
    }

    private func failRefreshWaiters(_ error: Error) {
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func registerDevice() async throws -> DeviceResponse {
        var request = URLRequest(url: APIConfig.authHost.appendingPathComponent("device"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("client_id", APIConfig.oauthClientID),
            ("device_id", KeychainStore.deviceID),
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let device = try? JSONDecoder().decode(DeviceResponse.self, from: data) else {
            throw RemoteAuthError.deviceRegistrationFailed
        }
        return device
    }

    private func pollForToken(deviceCode: String, interval: Int) async {
        await MainActor.run {
            isPolling = true
        }
        var pollInterval = interval
        defer {
            Task { @MainActor in
                isPolling = false
                loginUserCode = nil
            }
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: APIConfig.authHost.appendingPathComponent("token"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                ("client_id", APIConfig.oauthClientID),
                ("device_code", deviceCode),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ])

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 200 {
                    let result = try JSONDecoder().decode(TokenResponse.self, from: data)
                    KeychainStore.write(result.access_token, for: "access_token")
                    KeychainStore.write(result.refresh_token, for: "refresh_token")
                    await MainActor.run { isAuthorized = true }
                    return
                }

                if http.statusCode == 400 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    if body.contains("authorization_pending") {
                        continue
                    }
                    if body.contains("slow_down") {
                        pollInterval += 5
                        continue
                    }
                    if body.contains("expired_token") {
                        await MainActor.run { lastError = "Login code expired. Try again." }
                        return
                    }
                    await MainActor.run { lastError = body }
                    return
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { lastError = error.localizedDescription }
                }
                return
            }
        }
    }

    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        return Date().timeIntervalSince1970 >= exp
    }

    private func formBody(_ pairs: [(String, String)]) -> Data {
        let body = pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
