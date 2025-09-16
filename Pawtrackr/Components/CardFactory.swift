
import SwiftUI

struct CardFactory {
    @ViewBuilder
    static func makeClientCard(client: Client, onDelete: @escaping () -> Void) -> some View {
        ClientCard(client: client, onDelete: onDelete)
    }

    @ViewBuilder
    static func makePetCard(pet: Pet, activeVisit: Visit?, onViewDetails: @escaping () -> Void, onCheckIn: @escaping () -> Void, onCheckOut: @escaping () -> Void) -> some View {
        PetCard(pet: pet, activeVisit: activeVisit, onViewDetails: onViewDetails, onCheckIn: onCheckIn, onCheckOut: onCheckOut)
    }

    @ViewBuilder
    static func makeVisitTimelineRow(visit: Visit) -> some View {
        VisitTimelineRow(visit: visit)
    }
}
