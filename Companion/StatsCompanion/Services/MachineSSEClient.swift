import Foundation

final class MachineSSEClient: NSObject, URLSessionDataDelegate {
    private let machineID: String
    private let onUpdate: (RemoteUpdate) -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var authTask: Task<Void, Never>?
    private var connectionGeneration: UInt = 0
    private var rejectedToken: String?
    private var retriedAuthorization = false
    private var buffer = Data()
    private var stopped = false
    private var reconnectAttempts = 0

    private let delegateQueue = OperationQueue()
    private let callbackQueue = DispatchQueue.main

    init(machineID: String, onUpdate: @escaping (RemoteUpdate) -> Void) {
        self.machineID = machineID
        self.onUpdate = onUpdate
        super.init()
        delegateQueue.maxConcurrentOperationCount = 1
    }

    func start() {
        stopped = false
        retriedAuthorization = false
        rejectedToken = nil
        openConnection()
    }

    func stop() {
        stopped = true
        connectionGeneration &+= 1
        authTask?.cancel()
        authTask = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll()
    }

    private func openConnection() {
        guard !stopped,
              let url = URL(string: "\(APIConfig.apiHost.absoluteString)/v1/machine/\(machineID)/sse") else { return }
        connectionGeneration &+= 1
        let generation = connectionGeneration
        authTask?.cancel()

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let rejected = rejectedToken
        authTask = Task {
            do {
                let authorized = try await SystemStatsAPI.shared.authorizedRequest(request, rejectedToken: rejected)
                guard !stopped, connectionGeneration == generation, !Task.isCancelled else { return }
                rejectedToken = nil
                connect(authorized)
            } catch {
                guard !stopped, connectionGeneration == generation, !Task.isCancelled else { return }
                if error is RemoteAuthError || error is CancellationError { return }
                scheduleReconnect()
            }
        }
    }

    private func connect(_ request: URLRequest) {
        let urlSession: URLSession
        if let existing = self.session {
            urlSession = existing
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = .infinity
            config.timeoutIntervalForResource = .infinity
            let created = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
            self.session = created
            urlSession = created
        }

        buffer.removeAll()
        let task = urlSession.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !stopped, dataTask === task else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        if http.statusCode == 401 {
            completionHandler(.cancel)
            task = nil
            guard !retriedAuthorization else {
                stop()
                return
            }
            retriedAuthorization = true
            rejectedToken = String((dataTask.originalRequest?.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
            openConnection()
            return
        }
        guard http.statusCode == 200 else {
            completionHandler(.cancel)
            if [403, 404, 410].contains(http.statusCode) { stop() }
            return
        }
        retriedAuthorization = false
        reconnectAttempts = 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !stopped, dataTask === task else { return }
        buffer.append(data)
        let separator = Data("\n\n".utf8)
        while let range = buffer.range(of: separator) {
            let frame = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            parseFrame(frame)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !stopped, task === self.task else { return }
        self.task = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)
        reconnectAttempts += 1
        let generation = connectionGeneration
        callbackQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.connectionGeneration == generation else { return }
            self.openConnection()
        }
    }

    private func parseFrame(_ frame: Data) {
        guard let text = String(data: frame, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonText = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonText.isEmpty,
                  let jsonData = jsonText.data(using: .utf8),
                  let update = try? JSONDecoder().decode(RemoteUpdate.self, from: jsonData) else { continue }
            reconnectAttempts = 0
            callbackQueue.async { self.onUpdate(update) }
        }
    }
}

final class MachineStreamCoordinator {
    private var streams: [String: MachineSSEClient] = [:]

    func sync(machineIDs: [String], onUpdate: @escaping (String, RemoteUpdate) -> Void) {
        let ids = Set(machineIDs)
        for (id, stream) in streams where !ids.contains(id) {
            stream.stop()
            streams.removeValue(forKey: id)
        }
        for id in ids where streams[id] == nil {
            let stream = MachineSSEClient(machineID: id) { update in
                onUpdate(id, update)
            }
            streams[id] = stream
            stream.start()
        }
    }

    func stopAll() {
        streams.values.forEach { $0.stop() }
        streams.removeAll()
    }
}
