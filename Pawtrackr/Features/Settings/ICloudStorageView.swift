//
//  ICloudStorageView.swift
//  Pawtrackr
//
//  Insights into iCloud storage usage (Photos, Database).
//

import SwiftUI
import SwiftData

struct ICloudStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]
    @Query private var pets: [Pet]
    @Query private var visits: [Visit]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Usage Summary") {
                    HStack {
                        Label("Total Photos", systemImage: "photo.on.rectangle")
                        Spacer()
                        Text("\(totalPhotos)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Database Size", systemImage: "internaldrive")
                        Spacer()
                        Text(databaseSizeEstimate)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Media Optimization") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photo Sync Strategy")
                            .font(.headline)
                        Text("Pawtrackr automatically optimizes photos for iCloud to save space. High-resolution photos are downsampled while maintaining professional quality.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Storage Tips") {
                    Text("• Ensure all devices are on Wi-Fi for faster photo syncing.")
                    Text("• Older visit photos (>1 year) are prioritized for compression to keep your iCloud lean.")
                }
            }
            .navigationTitle("iCloud Storage")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var totalPhotos: Int {
        let clientPhotos = clients.filter { $0.photoData != nil }.count
        let petPhotos = pets.filter { $0.photoData != nil }.count
        let visitPhotos = visits.reduce(0) { count, visit in
            count + (visit.beforePhotoData != nil ? 1 : 0) + (visit.afterPhotoData != nil ? 1 : 0)
        }
        return clientPhotos + petPhotos + visitPhotos
    }
    
    private var databaseSizeEstimate: String {
        // Very rough estimate based on record counts
        let count = clients.count + pets.count + visits.count
        let kb = count * 2 // 2KB per record avg
        if kb > 1024 {
            return String(format: "%.1f MB", Double(kb) / 1024.0)
        }
        return "\(kb) KB"
    }
}
