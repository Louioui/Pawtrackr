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
        Feature(title: "Guided Hands-On Tour", description: "New here? We spotlight each tool and explain what it does, step by step — right on top of a sample salon.", icon: "hand.tap.fill", color: .blue),
        Feature(title: "Aggressive-Pet Safety Flag", description: "Pets marked aggressive now show a bold red warning across your client list, so the team handles them with care.", icon: "exclamationmark.triangle.fill", color: .red),
        Feature(title: "Explore, Then Start Fresh", description: "Play with realistic demo data, then wipe it in one tap from Settings to begin with your real business.", icon: "wand.and.stars", color: .purple),
        Feature(title: "Faster, Friendlier Setup", description: "A smoother animated welcome — and you can set a PIN or skip it for instant, passcode-free access.", icon: "bolt.fill", color: .orange)
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
