import Foundation

enum SystemWorkloadPolicy {
    static func heavyBackgroundWorkDeferralReason(
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> String? {
        if isLowPowerModeEnabled {
            return "low_power_mode"
        }

        switch thermalState {
        case .nominal, .fair:
            return nil
        case .serious:
            return "thermal_state_serious"
        case .critical:
            return "thermal_state_critical"
        @unknown default:
            return "thermal_state_unknown"
        }
    }
}
