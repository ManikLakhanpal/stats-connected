import SwiftUI

struct HostDetailView: View {
    let host: RemoteHost

    var body: some View {
        List {
            Section("Endpoint") {
                LabeledContent("Type", value: host.type.uppercased())
                LabeledContent("URL", value: host.url)
                LabeledContent("Status", value: host.lastStatus ?? "Unknown")
                if let latency = host.lastLatencyMs, latency > 0 {
                    LabeledContent("Latency", value: "\(latency) ms")
                }
            }

            if let history = host.history, !history.isEmpty {
                Section("Recent checks") {
                    ForEach(history) { bucket in
                        HStack {
                            Text(bucket.ts)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(bucket.status)
                                .foregroundStyle(bucket.status.lowercased() == "up" ? .green : .red)
                            Text(String(format: "%.0f%% up", bucket.uptime * 100))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let url = host.webURL {
                Section {
                    Link("Open in System Stats web", destination: url)
                }
            }
        }
        .navigationTitle(host.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
