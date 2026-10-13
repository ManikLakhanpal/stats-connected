import SwiftUI

struct FleetView: View {
    @StateObject private var viewModel = FleetViewModel()
    @ObservedObject private var auth = RemoteAuthService.shared

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasLoaded || (viewModel.isLoading && viewModel.sections.isEmpty) {
                    ProgressView("Loading fleet…")
                } else if viewModel.sections.isEmpty {
                    ContentUnavailableView(
                        viewModel.errorMessage == nil ? "No machines yet" : "Could not load machines",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text(viewModel.errorMessage ?? "Sign into System Stats on your Macs and turn on remote monitoring. Pull to refresh after that.")
                    )
                } else {
                    List {
                        ForEach(viewModel.sections) { section in
                            if let title = section.title {
                                Section(title) {
                                    fleetRows(section: section)
                                }
                            } else {
                                Section {
                                    fleetRows(section: section)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Fleet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        viewModel.onDisappear()
                        auth.logout()
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.refresh()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func fleetRows(section: FleetSection) -> some View {
        ForEach(section.machines) { machine in
            let current = viewModel.machine(for: machine.id) ?? machine
            NavigationLink {
                MachineDetailView(machine: current)
            } label: {
                MachineRow(machine: current)
            }
        }
        ForEach(section.hosts) { host in
            NavigationLink {
                HostDetailView(host: host)
            } label: {
                HostRow(host: host)
            }
        }
    }
}

private struct MachineRow: View {
    let machine: RemoteMachine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusDot(online: machine.online)
                Text(machine.displayName)
                    .font(.headline)
            }
            if !machine.subtitle.isEmpty {
                Text(machine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                metricColumn(title: "CPU", value: machine.modules?.cpuUsage, tint: .blue)
                metricColumn(title: "RAM", value: machine.modules?.ramUsage, tint: .orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricColumn(title: String, value: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentString(value))
                    .font(.caption.monospacedDigit())
            }
            UsageBar(fraction: value, tint: tint)
        }
    }
}

private struct HostRow: View {
    let host: RemoteHost

    var body: some View {
        HStack {
            Circle()
                .fill(colorForStatus(host.statusColorName))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.headline)
                Text(host.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorForStatus(_ name: String) -> Color {
        switch name {
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
}
