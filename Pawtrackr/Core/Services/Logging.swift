//
//  Logging.swift
//  Pawtrackr
//
//  Centralized OSLog infrastructure.
//

import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.pawtrackr.app"

    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let database = Logger(subsystem: subsystem, category: "Database")
    static let security = Logger(subsystem: subsystem, category: "Security")
    static let performance = Logger(subsystem: subsystem, category: "Performance")
    static let dataIntegrity = Logger(subsystem: subsystem, category: "DataIntegrity")
    static let cloudKit = Logger(subsystem: subsystem, category: "CloudKit")
    static let forecasting = Logger(subsystem: subsystem, category: "PredictiveForecasting")
}
