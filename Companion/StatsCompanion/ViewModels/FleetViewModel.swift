import Foundation

@MainActor
final class FleetViewModel: ObservableObject {
    @Published var sections: [FleetSection] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?
    @Published private(set) var machinesByID: [String: RemoteMachine] = [:]

    private let streamCoordinator = MachineStreamCoordinator()
    private var refreshTask: Task<Void, Never>?

    func onAppear() {
        Task { await refresh() }
    }

    func onDisappear() {
        streamCoordinator.stopAll()
        refreshTask?.cancel()
    }

    func refresh() async {
        guard RemoteAuthService.shared.isAuthorized else { return }
        isLoading = sections.isEmpty
        errorMessage = nil
        do {
            let snapshot = try await SystemStatsAPI.shared.fetchSnapshot()
            applySnapshot(snapshot)
            syncStreams()
        } catch is CancellationError {
            return
        } catch RemoteAuthError.unauthorized {
            sections = []
            machinesByID = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        isLoading = false
    }

    func machine(for id: String) -> RemoteMachine? {
        machinesByID[id]
    }

    private func applySnapshot(_ snapshot: RemoteSnapshot) {
        machinesByID = Dictionary(uniqueKeysWithValues: snapshot.machines.map { ($0.id, $0) })
        sections = FleetLayout.buildSections(from: snapshot)
    }

    private func syncStreams() {
        let ids = machinesByID.keys.sorted()
        streamCoordinator.sync(machineIDs: ids) { [weak self] id, update in
            Task { @MainActor in
                self?.applyUpdate(id: id, update: update)
            }
        }
    }

    private func applyUpdate(id: String, update: RemoteUpdate) {
        guard let machine = machinesByID[id] else { return }
        let merged = machine.applying(update)
        machinesByID[id] = merged
        sections = sections.map { section in
            FleetSection(
                id: section.id,
                title: section.title,
                machines: section.machines.map { $0.id == id ? merged : $0 },
                hosts: section.hosts
            )
        }
    }
}
