import Foundation

enum APIError: LocalizedError {
    case http(status: Int, body: String)
    case decoding(underlying: Error, body: String)
    case unexpectedShape(body: String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "Request failed (\(status)). \(body)"
        case .decoding(let underlying, let body):
            return "Could not read the machine list. \(underlying.localizedDescription) \(body)"
        case .unexpectedShape(let body):
            return "Unexpected response. \(body)"
        }
    }
}

final class SystemStatsAPI {
    static let shared = SystemStatsAPI()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    func fetchSnapshot() async throws -> RemoteSnapshot {
        let machines = try await fetchMachines()
        async let hosts = fetchHosts()
        async let groups = fetchGroups()
        async let order = fetchAccountOrder()
        let loadedHosts = (try? await hosts) ?? []
        let loadedGroups = (try? await groups) ?? []
        let loadedOrder = (try? await order) ?? RemoteAccountOrder(machines: [], hosts: [])
        return RemoteSnapshot(
            machines: machines,
            hosts: loadedHosts,
            groups: loadedGroups,
            order: loadedOrder
        )
    }

    func fetchMachines() async throws -> [RemoteMachine] {
        try await fetchList(path: "/v1/machine")
    }

    func fetchHosts(historyWindow: String = "") async throws -> [RemoteHost] {
        let path = historyWindow.isEmpty ? "/v1/host" : "/v1/host?history=\(historyWindow)"
        return try await fetchList(path: path)
    }

    func fetchGroups() async throws -> [RemoteGroup] {
        try await fetchList(path: "/v1/group")
    }

    func fetchAccountOrder() async throws -> RemoteAccountOrder {
        let data = try await fetchData(path: "/v1/account")
        let account = try JSONDecoder().decode(RemoteAccountResponse.self, from: data)
        return RemoteAccountOrder(
            machines: account.settings?.order ?? [],
            hosts: account.settings?.hostsOrder ?? []
        )
    }

    private struct RemoteAccountResponse: Decodable {
        let settings: Settings?
        struct Settings: Decodable {
            let order: [String]?
            let hostsOrder: [String]?
        }
    }

    private func fetchList<T: Decodable>(path: String) async throws -> [T] {
        let data = try await fetchData(path: path)
        return try decodeList(T.self, from: data)
    }

    private func decodeList<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([T].self, from: data) {
            return list
        }

        let payload = try listElements(from: data)
        var items: [T] = []
        var firstError: Error?
        for element in payload {
            guard JSONSerialization.isValidJSONObject(element) else { continue }
            let itemData = try JSONSerialization.data(withJSONObject: element)
            do {
                items.append(try decoder.decode(T.self, from: itemData))
            } catch {
                firstError = firstError ?? error
            }
        }
        if items.isEmpty, !payload.isEmpty, let firstError {
            let snippet = String(data: data.prefix(280), encoding: .utf8) ?? ""
            throw APIError.decoding(underlying: firstError, body: snippet)
        }
        return items
    }

    private func listElements(from data: Data) throws -> [Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let array = object as? [Any] {
            return array
        }
        if let dict = object as? [String: Any] {
            for key in ["machines", "hosts", "groups", "data", "items", "results"] {
                if let array = dict[key] as? [Any] {
                    return array
                }
            }
        }
        let snippet = String(data: data.prefix(280), encoding: .utf8) ?? ""
        throw APIError.unexpectedShape(body: snippet)
    }

    private func fetchData(path: String) async throws -> Data {
        guard let url = URL(string: APIConfig.apiHost.absoluteString + path) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        let (data, response) = try await authorizedData(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(data: data.prefix(280), encoding: .utf8) ?? ""
            throw APIError.http(status: status, body: snippet)
        }
        return data
    }

    func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = try await authorizedRequest(request)
        var result = try await session.data(for: request)
        if (result.1 as? HTTPURLResponse)?.statusCode == 401 {
            let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
            request = try await authorizedRequest(request, rejectedToken: token)
            result = try await session.data(for: request)
        }
        if (result.1 as? HTTPURLResponse)?.statusCode == 401 {
            await MainActor.run { RemoteAuthService.shared.logout() }
            throw RemoteAuthError.unauthorized
        }
        return result
    }

    func authorizedRequest(_ request: URLRequest, rejectedToken: String? = nil) async throws -> URLRequest {
        let token = try await RemoteAuthService.shared.authorize(rejectedToken: rejectedToken)
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
