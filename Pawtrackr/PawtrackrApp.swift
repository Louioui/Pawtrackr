//
//  PawtrackrApp.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData
import OSLog

@main
struct PawtrackrApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [Client.self, Pet.self, Visit.self, VisitItem.self, Service.self, Payment.self])
        }
    }
}
