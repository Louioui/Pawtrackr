
import SwiftUI

struct ActiveVisitRow: View {
    let visit: Visit
    @StateObject private var timer = VisitTimer()

    var body: some View {
        Card(elevation: .regular, accent: .leading(.color(DS.ColorToken.session), thickness: 4)) {
            HStack(spacing: 12) {
                AvatarView(.pet(species: visit.pet?.species, gender: visit.pet?.gender,
                                name: visit.pet?.name ?? "Unknown", imageData: visit.pet?.photoData), size: .md)
                VStack(alignment: .leading) {
                    Text(visit.pet?.name ?? "Unknown").font(.headline)
                    Text(visit.pet?.owner?.fullName ?? "").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()

                // Live-ticking timer
                Text(timer.formattedElapsed)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if let pet = visit.pet {
                    NavigationLink(destination: CheckoutView(pet: pet, visit: visit)) {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Session options")
                    .accessibilityIdentifier("dashboard.activeSession.checkoutButton")
                }
            }
        }
        .onAppear {
            timer.load(startedAt: visit.startedAt, endedAt: visit.endedAt)
        }
    }
}
