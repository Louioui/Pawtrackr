//
//  TransformationView.swift
//  Pawtrackr
//
//  A high-impact view showing Before & After photos side-by-side.
//

import SwiftUI

struct TransformationView: View {
    let beforeData: Data?
    let afterData: Data?
    let petName: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let beforeData, let afterData {
                    comparisonLayout(before: beforeData, after: afterData)
                } else {
                    ContentUnavailableView("Missing Photos", systemImage: "photo.on.rectangle", description: Text("Both Before and After photos are required for a transformation view."))
                }
            }
            .padding()
            .navigationTitle("\(petName)'s Transformation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: "Check out \(petName)'s grooming transformation at Pawtrackr!") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func comparisonLayout(before: Data, after: Data) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                photoFrame(data: before)
                Text("BEFORE")
                    .font(.caption.bold())
                    .padding(6)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(10)
            }
            
            Divider()
            
            ZStack(alignment: .bottomLeading) {
                photoFrame(data: after)
                Text("AFTER")
                    .font(.caption.bold())
                    .padding(6)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(radius: 10)
    }
    
    private func photoFrame(data: Data) -> some View {
        #if canImport(UIKit)
        if let img = UIImage(data: data) {
            return AnyView(Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped())
        }
        #elseif canImport(AppKit)
        if let img = NSImage(data: data) {
            return AnyView(Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped())
        }
        #endif
        return AnyView(Color.gray)
    }
}
