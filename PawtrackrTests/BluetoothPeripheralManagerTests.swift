import XCTest

#if canImport(CoreBluetooth)
import CoreBluetooth
@testable import Pawtrackr

final class BluetoothPeripheralManagerTests: XCTestCase {
    func testCentralManagerOptions_EnableStateRestoration() {
        let options = BluetoothPeripheralManager.centralManagerOptions()

        XCTAssertEqual(options[CBCentralManagerOptionShowPowerAlertKey] as? Bool, true)
        XCTAssertEqual(
            options[CBCentralManagerOptionRestoreIdentifierKey] as? String,
            BluetoothPeripheralManager.centralManagerRestorationIdentifier
        )
        XCTAssertFalse(BluetoothPeripheralManager.centralManagerRestorationIdentifier.isEmpty)
    }
}
#endif
