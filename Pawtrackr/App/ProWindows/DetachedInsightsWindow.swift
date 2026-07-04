import SwiftUI

struct DetachedInsightsWindow: View {
    var body: some View {
        NavigationStack {
            InsightsView()
        }
        .frame(minWidth: 760, minHeight: 560)
        .privacyBlur()
    }
}
