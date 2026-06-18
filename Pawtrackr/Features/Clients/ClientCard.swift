

//
//  ClientCard.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI

struct ClientCard: View {
    let client: Client
    var namespace: Namespace.ID? = nil
    /// When set, the list (which groups clients via a fresh store query) is the
    /// source of truth for the "In Session" state. Reading `client.hasActiveVisit`
    /// off the in-memory relationship goes stale after a cross-context checkout,
    /// so prefer the caller's query-derived value when available.
    var isInProgressOverride: Bool? = nil

    private var visualState: VisualState {
        VisualState(client: client, isInProgressOverride: isInProgressOverride)
    }
    private var isInProgress: Bool { visualState.isInProgress }
    private var isAggressive: Bool { visualState.showsAggressiveWarning }
    private var needsAttention: Bool { visualState.needsAttention }
    private var hasMissingInfo: Bool { client.phone == nil || client.email == nil }
    
    @State private var pulse: Bool = false

    var body: some View {
        let state = visualState
        let accentColor: Color? = switch state.accentKind {
        case .safety:
            DS.ColorToken.danger
        case .inProgress:
            DS.ColorToken.success
        case .attention:
            Color.orange
        case .none:
            nil
        }

        Card(elevation: .regular, accent: accentColor != nil ? .leading(.color(accentColor!), thickness: 4) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                if state.showsAggressiveWarning { aggressiveBanner }
                header
                phoneInfo
                petsInfo
            }
        }
        .id(state.identityKey)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let namespace {
                AvatarView(.client(name: client.fullName), size: .sm)
                    .matchedGeometryEffect(id: "avatar-\(client.id)", in: namespace)
            } else {
                AvatarView(.client(name: client.fullName), size: .sm)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(client.fullName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .id("name-\(client.id)")
            }
            
            Spacer()
            // Aggressive state is shown by the prominent banner above; keep the
            // header chips for status only to avoid a redundant double-warning.
            if isInProgress {
                Chip.success("In Session")
            } else if needsAttention {
                Chip.warning(NSLocalizedString("clients.needs_attention", value: "Needs Attention", comment: ""))
            } else if hasMissingInfo {
                Chip.info("Missing Info")
            }
        }
    }

    /// Loud, full-width safety warning shown at the top of the card whenever any
    /// of the client's pets is flagged aggressive. Staff see the danger before
    /// they tap into the client. Mirrors the detail-view safety banner.
    private var aggressiveBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(NSLocalizedString("pet.safety.aggressive_badge", value: "Aggressive — handle with care", comment: ""))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(NSLocalizedString("pet.safety.aggressive_a11y", value: "Warning: this pet is marked aggressive. Handle with care.", comment: ""))
    }

    @ViewBuilder
    private var phoneInfo: some View {
        if let phone = client.phone, !phone.isEmpty {
            Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private var petsInfo: some View {
        HStack(alignment: .center) {
            HStack(spacing: -12) { // Tighter stacking for avatars
                ForEach((client.pets ?? []).prefix(3)) { pet in
                    AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name), size: .sm, ringWidth: 2)
                }
            }
            
            Text((client.pets ?? []).map(\.name).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 16)
            
            Spacer()
        }
    }


}

extension ClientCard {
    struct VisualState: Equatable {
        enum AccentKind: String, Equatable {
            case safety
            case inProgress
            case attention
        }

        let showsAggressiveWarning: Bool
        let isInProgress: Bool
        let needsAttention: Bool
        let accentKind: AccentKind?
        let identityKey: String

        init(client: Client, isInProgressOverride: Bool?) {
            let pets = client.pets ?? []
            showsAggressiveWarning = pets.contains { $0.isAggressive }
            isInProgress = isInProgressOverride ?? client.hasActiveVisit
            needsAttention = pets.contains { $0.needsAttention }

            if showsAggressiveWarning {
                accentKind = .safety
            } else if isInProgress {
                accentKind = .inProgress
            } else if needsAttention {
                accentKind = .attention
            } else {
                accentKind = nil
            }

            let behaviorSignature = pets
                .sorted { $0.uuid.uuidString < $1.uuid.uuidString }
                .map { pet in
                    let tags = pet.behaviorTags
                        .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
                        .joined(separator: ",")
                    return "\(pet.uuid.uuidString):\(tags)"
                }
                .joined(separator: "|")

            identityKey = [
                client.uuid.uuidString,
                "safety:\(showsAggressiveWarning)",
                "accent:\(accentKind?.rawValue ?? "none")",
                "behaviors:\(behaviorSignature)"
            ].joined(separator: "|")
        }
    }
}
