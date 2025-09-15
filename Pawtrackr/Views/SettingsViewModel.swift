
//
//  SettingsViewModel.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @AppStorage("pruningThreshold") var pruningThreshold: PruningThreshold = .never

    enum PruningThreshold: String, CaseIterable, Identifiable {
        case oneYear = "1 Year"
        case threeYears = "3 Years"
        case fiveYears = "5 Years"
        case never = "Never"

        var id: Self { self }

        var date: Date? {
            switch self {
            case .oneYear:
                return Calendar.current.date(byAdding: .year, value: -1, to: .now)
            case .threeYears:
                return Calendar.current.date(byAdding: .year, value: -3, to: .now)
            case .fiveYears:
                return Calendar.current.date(byAdding: .year, value: -5, to: .now)
            case .never:
                return nil
            }
        }
    }
}
