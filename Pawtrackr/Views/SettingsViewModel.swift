
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
        case oneYear, threeYears, fiveYears, never

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .oneYear:
                return "settings.data_management.prune.1y"
            case .threeYears:
                return "settings.data_management.prune.3y"
            case .fiveYears:
                return "settings.data_management.prune.5y"
            case .never:
                return "settings.data_management.prune.never"
            }
        }

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
