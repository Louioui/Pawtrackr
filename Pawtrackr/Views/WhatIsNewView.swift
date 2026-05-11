import SwiftUI

struct WhatIsNewView: View {
    var onDismiss: () -> Void
    
    struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: String
        let color: Color
    }
    
    let features = [
        Feature(title: "Inventory Tracking", description: "Monitor your supplies and costs directly in the app.", icon: "shippingbox.fill", color: .blue),
        Feature(title: "CSV Data Import", description: "Easily migrate your existing clients from other software.", icon: "square.and.arrow.down.fill", color: .green),
        Feature(title: "Team Management", description: "Assign staff to visits and track performance.", icon: "person.2.fill", color: .purple),
        Feature(title: "Security Hardening", description: "Enhanced privacy screen and biometric security.", icon: "lock.shield.fill", color: .red)
    ]
    
    var body: some View {
        VStack(spacing: 30) {
            Text("What's New in Pawtrackr")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 40)
            
            VStack(alignment: .leading, spacing: 25) {
                ForEach(features) { feature in
                    HStack(spacing: 20) {
                        Image(systemName: feature.icon)
                            .font(.title)
                            .foregroundStyle(feature.color)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
}
