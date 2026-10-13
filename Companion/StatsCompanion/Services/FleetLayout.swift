import Foundation

enum FleetLayout {
    static func buildSections(from snapshot: RemoteSnapshot) -> [FleetSection] {
        let machineIndex = Dictionary(snapshot.order.machines.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let hostIndex = Dictionary(snapshot.order.hosts.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let groupById = Dictionary(snapshot.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let sortedMachines = snapshot.machines.sorted { a, b in
            let ia = machineIndex[a.id] ?? Int.max
            let ib = machineIndex[b.id] ?? Int.max
            if ia != ib { return ia < ib }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        let sortedHosts = snapshot.hosts.sorted { a, b in
            let ia = hostIndex[a.id] ?? Int.max
            let ib = hostIndex[b.id] ?? Int.max
            if ia != ib { return ia < ib }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        var machinesByGroup: [String: [RemoteMachine]] = [:]
        var ungroupedMachines: [RemoteMachine] = []
        for m in sortedMachines {
            if let gid = m.groupID, !gid.isEmpty, groupById[gid] != nil {
                machinesByGroup[gid, default: []].append(m)
            } else {
                ungroupedMachines.append(m)
            }
        }

        var hostsByGroup: [String: [RemoteHost]] = [:]
        var ungroupedHosts: [RemoteHost] = []
        for h in sortedHosts {
            if let gid = h.group, !gid.isEmpty, groupById[gid] != nil {
                hostsByGroup[gid, default: []].append(h)
            } else {
                ungroupedHosts.append(h)
            }
        }

        var sections: [FleetSection] = []
        if !ungroupedMachines.isEmpty || !ungroupedHosts.isEmpty {
            sections.append(FleetSection(id: "", title: nil, machines: ungroupedMachines, hosts: ungroupedHosts))
        }
        for group in snapshot.groups {
            let machines = machinesByGroup[group.id] ?? []
            let hosts = hostsByGroup[group.id] ?? []
            if !machines.isEmpty || !hosts.isEmpty {
                sections.append(FleetSection(id: group.id, title: group.name, machines: machines, hosts: hosts))
            }
        }
        return sections
    }
}
