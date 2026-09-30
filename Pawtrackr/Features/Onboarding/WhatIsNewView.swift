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
    
    /// What changed in this version. It shows once per version, on the
    /// first launch after an update.
    let features = [
        Feature(title: AppLocalization.localized("whats_new.local_data.title", value: "Your Data Stays on This Device"), description: AppLocalization.localized("whats_new.local_data.description", value: "iCloud sync is off. Everything already here stays, and from now on each iPhone, iPad and Mac keeps its own records. Export a copy anytime in Settings › Data Export."), icon: "icloud.slash.fill", color: .blue),
        Feature(title: AppLocalization.localized("whats_new.academy.title", value: "Pawtrackr Academy"), description: AppLocalization.localized("whats_new.academy.description", value: "Learn the app in five short chapters with hands-on missions, in a practice salon that never touches your real clients. Start it in Settings › About."), icon: "graduationcap.fill", color: .purple),
        Feature(title: AppLocalization.localized("whats_new.exports.title", value: "Better Reports and Exports"), description: AppLocalization.localized("whats_new.exports.description", value: "The business report PDF now shows trends, charts and highlights, and CSV files open cleanly in Excel and Numbers. Send them by AirDrop, Messages or Mail."), icon: "chart.bar.doc.horizontal.fill", color: .orange),
        Feature(title: AppLocalization.localized("whats_new.missing_info.title", value: "Smarter Missing Info Filter"), description: AppLocalization.localized("whats_new.missing_info.description", value: "Clients without an emergency contact, phone or email now show up under Missing Info, and their cards say what to add."), icon: "person.crop.circle.badge.exclamationmark", color: .red),
        Feature(title: AppLocalization.localized("whats_new.checkout.title", value: "Roomier, Simpler Checkout"), description: AppLocalization.localized("whats_new.checkout.description", value: "Checkout is wider on the Mac, and the tip step is gone: the total is your services, or the amount you type."), icon: "creditcard.fill", color: .green)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrolls on small iPhones and at large text sizes, so Continue
            // stays on screen.
            ScrollView {
                VStack(spacing: 30) {
                    Text(AppLocalization.localized("whats_new.title", value: "What's New in Pawtrackr"))
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 25) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 20) {
                                Image(systemName: feature.icon)
                                    .font(.title)
                                    .foregroundStyle(feature.color)
                                    .frame(width: 40)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                onDismiss()
            } label: {
                Text(AppLocalization.localized("whats_new.continue", value: "Continue"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 30)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 560, idealHeight: 680)
        #endif
    }
}
