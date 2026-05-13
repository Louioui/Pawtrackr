import SwiftUI

/// A view modifier that applies a staggered, cascading fade-in and slide transition to list items.
struct StaggeredEntryModifier: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(.snappy(duration: 0.5).delay(Double(index) * 0.05)) {
                    isVisible = true
                }
            }
    }
}

/// A premium, animated progress ring for grooming timers.
struct GroomingProgressRing: View {
    let progress: Double // 0.0 to 1.0
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.5), value: progress)
        }
    }
}

extension View {
    func staggeredEntry(index: Int) -> some View {
        modifier(StaggeredEntryModifier(index: index))
    }
}
