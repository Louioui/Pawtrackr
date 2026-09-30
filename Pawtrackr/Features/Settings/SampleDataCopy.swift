//
//  SampleDataCopy.swift
//  Pawtrackr
//
//  Wording Settings uses for the sample clients a salon still has, and for
//  removing them.
//

import Foundation

enum SampleDataCopy {
    static var removeTitle: String {
        AppLocalization.localized("sample_data.remove.title", value: "Remove Sample Clients?")
    }

    static var removeConfirm: String {
        AppLocalization.localized("sample_data.remove.confirm", value: "Remove Sample Clients")
    }

    /// Names every client that will go, plus any pet someone added under
    /// them, so nothing disappears without being listed first.
    static func removeMessage(for inventory: SampleDataInventory) -> String {
        let names = ListFormatter.localizedString(byJoining: inventory.clientNames)
        var message = String(
            format: AppLocalization.localized(
                "sample_data.remove.message_fmt",
                value: "This deletes the sample clients %@ with their pets, visits and payments on this device. Your own clients aren't touched."
            ),
            names
        )
        if !inventory.addedPetNames.isEmpty {
            message += " " + String(
                format: AppLocalization.localized(
                    "sample_data.remove.added_pets_fmt",
                    value: "Pets added to these clients are deleted too: %@."
                ),
                ListFormatter.localizedString(byJoining: inventory.addedPetNames)
            )
        }
        if inventory.examplePriceCount > 0 {
            message += " " + AppLocalization.localized(
                "sample_data.remove.example_prices",
                value: "The example service prices added with them are cleared too. Prices you set or changed stay."
            )
        }
        return message
    }

    static var settingsTitle: String {
        AppLocalization.localized("settings.sample.title", value: "Sample Clients")
    }

    static func loadedCaption(for inventory: SampleDataInventory) -> String {
        String(
            format: AppLocalization.localized(
                "settings.sample.loaded_caption_fmt",
                value: "%@ are practice clients. Removing them leaves your own clients alone."
            ),
            ListFormatter.localizedString(byJoining: inventory.clientNames)
        )
    }
}
