import Foundation

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String
}

struct DeviceResponse: Codable {
    let device_code: String
    let user_code: String
    let verification_uri_complete: URL
    let interval: Int?
}

struct RemoteMachine: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let online: Bool
    let groupID: String?
    let lastSeenTS: String?
    let details: RemoteMachineDetails?
    let modules: RemoteModules?

    enum CodingKeys: String, CodingKey {
        case id, name, online, groupID, lastSeenTS, details, modules
        case groupId
        case group
    }

    init(id: String, name: String?, online: Bool, groupID: String?, lastSeenTS: String?, details: RemoteMachineDetails?, modules: RemoteModules?) {
        self.id = id
        self.name = name
        self.online = online
        self.groupID = groupID
        self.lastSeenTS = lastSeenTS
        self.details = details
        self.modules = modules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        online = (try? container.decode(Bool.self, forKey: .online)) ?? false
        groupID = Self.optionalString(container, .groupID)
            ?? Self.optionalString(container, .groupId)
            ?? Self.optionalString(container, .group)
        lastSeenTS = try container.decodeIfPresent(String.self, forKey: .lastSeenTS)
        details = try? container.decodeIfPresent(RemoteMachineDetails.self, forKey: .details) ?? nil
        modules = try? container.decodeIfPresent(RemoteModules.self, forKey: .modules) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(online, forKey: .online)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encodeIfPresent(lastSeenTS, forKey: .lastSeenTS)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encodeIfPresent(modules, forKey: .modules)
    }

    private static func optionalString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let model = details?.system?.model, !model.isEmpty { return model }
        return id
    }

    var subtitle: String {
        guard let os = details?.system?.os else { return "" }
        if let name = os.name, let version = os.version { return "\(name) \(version)" }
        return os.name ?? ""
    }

    var webURL: URL? {
        URL(string: "\(APIConfig.appHost.absoluteString)/machine/\(id)")
    }

    func applying(_ update: RemoteUpdate) -> RemoteMachine {
        RemoteMachine(
            id: id,
            name: name,
            online: update.online ?? online,
            groupID: groupID,
            lastSeenTS: update.lastSeenTS ?? lastSeenTS,
            details: details,
            modules: update.modules ?? modules
        )
    }
}

struct RemoteModules: Codable, Hashable {
    let cpu: [String: RemoteCPUModule]?
    let ram: RemoteRAMModule?

    enum CodingKeys: String, CodingKey {
        case cpu, ram
    }

    init(cpu: [String: RemoteCPUModule]?, ram: RemoteRAMModule?) {
        self.cpu = cpu
        self.ram = ram
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dict = try? container.decode([String: RemoteCPUModule].self, forKey: .cpu) {
            cpu = dict
        } else if let list = try? container.decode([RemoteCPUModule].self, forKey: .cpu) {
            cpu = Dictionary(uniqueKeysWithValues: list.enumerated().map { ("\($0.offset)", $0.element) })
        } else {
            cpu = nil
        }
        ram = try? container.decode(RemoteRAMModule.self, forKey: .ram)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cpu, forKey: .cpu)
        try container.encodeIfPresent(ram, forKey: .ram)
    }

    var cpuUsage: Double? {
        guard let cpu else { return nil }
        let values = cpu.values.compactMap(\.usage)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var ramUsage: Double? {
        guard let ram, ram.total > 0 else { return nil }
        return ram.used / ram.total
    }
}

struct RemoteCPUModule: Codable, Hashable {
    let usage: Double?
}

struct RemoteRAMModule: Codable, Hashable {
    let total: Double
    let used: Double
}

struct RemoteUpdate: Codable {
    let online: Bool?
    let modules: RemoteModules?
    let lastSeenTS: String?
}

struct RemoteGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let parentID: String?
    let order: Int?
}

struct RemoteMachineDetails: Codable, Hashable {
    let system: RemoteMachineSystem?
}

struct RemoteMachineSystem: Codable, Hashable {
    let platform: String?
    let model: String?
    let os: RemoteMachineOS?
}

struct RemoteMachineOS: Codable, Hashable {
    let name: String?
    let version: String?
}

struct RemoteAccountOrder: Codable {
    let machines: [String]
    let hosts: [String]
}

struct RemoteSnapshot {
    let machines: [RemoteMachine]
    let hosts: [RemoteHost]
    let groups: [RemoteGroup]
    let order: RemoteAccountOrder
}

struct RemoteHost: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String?
    let url: String
    let group: String?
    let lastStatus: String?
    let lastLatencyMs: Int64?
    let history: [RemoteHostBucket]?

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        return url
    }

    var subtitle: String {
        var parts = [type.uppercased()]
        if let latency = lastLatencyMs, latency > 0 {
            parts.append("\(latency) ms")
        }
        return parts.joined(separator: " · ")
    }

    var isUp: Bool {
        lastStatus?.lowercased() == "up"
    }

    var statusColorName: String {
        switch lastStatus?.lowercased() {
        case "up": return "green"
        case "down": return "red"
        case "degraded": return "yellow"
        default: return "gray"
        }
    }

    var webURL: URL? {
        URL(string: "\(APIConfig.appHost.absoluteString)/host/\(id)")
    }
}

struct RemoteHostBucket: Codable, Hashable, Identifiable {
    var id: String { ts }
    let ts: String
    let status: String
    let uptime: Double
    let count: Int
}

struct FleetSection: Identifiable {
    let id: String
    let title: String?
    let machines: [RemoteMachine]
    let hosts: [RemoteHost]
}
