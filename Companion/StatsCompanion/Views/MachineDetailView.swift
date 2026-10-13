import SwiftUI

struct MachineDetailView: View {
    let machine: RemoteMachine

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Online", value: machine.online ? "Yes" : "No")
                if let lastSeen = machine.lastSeenTS, !lastSeen.isEmpty {
                    LabeledContent("Last seen", value: lastSeen)
                }
            }

            Section("System") {
                if let model = machine.details?.system?.model {
                    LabeledContent("Model", value: model)
                }
                if !machine.subtitle.isEmpty {
                    LabeledContent("OS", value: machine.subtitle)
                }
            }

            Section("Metrics") {
                LabeledContent("CPU") {
                    Text(percentString(machine.modules?.cpuUsage))
                }
                UsageBar(fraction: machine.modules?.cpuUsage, tint: .blue)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))

                LabeledContent("RAM") {
                    Text(percentString(machine.modules?.ramUsage))
                }
                if let ram = machine.modules?.ram {
                    Text("\(formatBytes(ram.used)) / \(formatBytes(ram.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                UsageBar(fraction: machine.modules?.ramUsage, tint: .orange)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
            }

            if let url = machine.webURL {
                Section {
                    Link("Open in System Stats web", destination: url)
                }
            }
        }
        .navigationTitle(machine.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatBytes(_ value: Double) -> String {
        let gb = value / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = value / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
