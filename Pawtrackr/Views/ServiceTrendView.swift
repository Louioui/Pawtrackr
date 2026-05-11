
//
//  ServiceTrendView.swift
//  Pawtrackr
//
//  Created by Assistant on 9/15/25.
//

import SwiftUI
import SwiftData
import Charts
import OSLog

private let serviceTrendLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ServiceTrend")

struct ServiceTrendView: View {
    let serviceName: String
    @State private var data: [ServiceDaySummary] = []
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack {
            if #available(iOS 16.0, *) {
                Chart(data) { summary in
                    BarMark(
                        x: .value("Date", summary.day, unit: .day),
                        y: .value("Count", summary.count)
                    )
                }
                .padding()
            } else {
                Text("Charts are not available on this OS version.")
            }
        }
        .navigationTitle(serviceName)
        .task(id: serviceName) {
            await fetchData()
        }
    }

    private func fetchData() async {
        let container = modelContext.container
        let name = serviceName
        do {
            let ids: [PersistentIdentifier] = try await Task.detached(priority: .userInitiated) {
                let bgCtx = ModelContext(container)
                let predicate = #Predicate<ServiceDaySummary> { $0.serviceName == name }
                let descriptor = FetchDescriptor<ServiceDaySummary>(predicate: predicate, sortBy: [SortDescriptor(\ServiceDaySummary.day)])
                return try bgCtx.fetch(descriptor).map(\.persistentModelID)
            }.value
            data = ids.compactMap { modelContext.model(for: $0) as? ServiceDaySummary }
        } catch {
            serviceTrendLog.error("Failed to fetch service trend data: \(error.localizedDescription, privacy: .public)")
        }
    }
}
