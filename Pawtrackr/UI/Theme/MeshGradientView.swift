import SwiftUI

/// Adds a dynamic, interactive MeshGradient background to any view.
struct MeshGradientView: View {
    @State private var time: Float = 0
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + sin(time) * 0.1, 0.5 + cos(time) * 0.1], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1]
        ], colors: [
            .blue.opacity(0.1), .purple.opacity(0.1), .blue.opacity(0.1),
            .purple.opacity(0.1), .white.opacity(0.2), .purple.opacity(0.1),
            .blue.opacity(0.1), .purple.opacity(0.1), .blue.opacity(0.1)
        ])
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            time += 0.05
        }
    }
}
