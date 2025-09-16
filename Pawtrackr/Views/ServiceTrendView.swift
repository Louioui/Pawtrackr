
//
//  ServiceTrendView.swift
//  Pawtrackr
//
//  Created by Assistant on 9/15/25.
//

import SwiftUI
import SwiftData
import Charts

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
        .onAppear(perform: fetchData)
    }

    private func fetchData() {
        let predicate = #Predicate<ServiceDaySummary> { $0.serviceName == serviceName }
        let descriptor = FetchDescriptor<ServiceDaySummary>(predicate: predicate, sortBy: [SortDescriptor(\ServiceDaySummary.day)])
        do {
            data = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching service data: \(error)")
        }
    }
}
