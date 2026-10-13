import SwiftUI

struct UsageBar: View {
    let fraction: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                if let fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
        }
        .frame(height: 4)
    }
}

struct StatusDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }
}

func percentString(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int((value * 100).rounded()))%"
}
