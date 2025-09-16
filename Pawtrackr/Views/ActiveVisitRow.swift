
import SwiftUI

struct ActiveVisitRow: View {
    let visit: Visit
    @StateObject private var timer = VisitTimer()

    var body: some View {
        Card {
            HStack(spacing: 12) {
                AvatarView(.pet(species: visit.pet.species, gender: visit.pet.gender,
                                name: visit.pet.name, imageData: visit.pet.photoData), size: .md)
                VStack(alignment: .leading) {
                    Text(visit.pet.name).font(.headline)
                    Text(visit.pet.owner?.fullName ?? "").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                
                // Live-ticking timer
                Text(timer.formattedElapsed)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                
                NavigationLink(destination: CheckoutView(pet: visit.pet)) {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Session options")
            }
        }
        .onAppear {
            timer.load(startedAt: visit.startedAt, endedAt: visit.endedAt)
        }
    }
}
