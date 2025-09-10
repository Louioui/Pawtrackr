//
//  Notification+Extensions.swift
//  Pawtrackr
//
//  Centralized app-wide notification names.
//

import Foundation

extension Notification.Name {
    /// Posted after a successful checkout so views (Clients, Pet Detail, Recent History, Insights) can refresh.
    static let visitDidComplete = Notification.Name("visitDidComplete")
}
