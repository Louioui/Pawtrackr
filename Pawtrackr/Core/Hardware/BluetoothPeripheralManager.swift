//
//  BluetoothPeripheralManager.swift
//  Pawtrackr
//
//  CoreBluetooth bridge for physical retail peripherals.
//

import Foundation
import OSLog

struct POSPeripheralDescriptor: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case thermalPrinter
        case cashDrawer
        case rfidScanner
        case unknown
    }

    let id: UUID
    let name: String
    let kind: Kind
    let rssi: Int
}

enum PeripheralError: Error, Equatable, LocalizedError {
    case bluetoothHardwareOffline
    case bluetoothUnavailable(String)
    case printerNotConnected
    case printerWriteCharacteristicUnavailable
    case peripheralNotFound(UUID)
    case connectionTimedOut
    case transmissionTimedOut
    case transmissionFailed(String)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .bluetoothHardwareOffline:
            return "Bluetooth hardware is offline."
        case .bluetoothUnavailable(let state):
            return "Bluetooth is unavailable: \(state)."
        case .printerNotConnected:
            return "No thermal receipt printer is connected."
        case .printerWriteCharacteristicUnavailable:
            return "The connected printer does not expose a writable ESC/POS characteristic."
        case .peripheralNotFound(let id):
            return "No discovered peripheral matched \(id.uuidString)."
        case .connectionTimedOut:
            return "The peripheral connection timed out."
        case .transmissionTimedOut:
            return "The receipt transmission timed out."
        case .transmissionFailed(let reason):
            return "Receipt transmission failed: \(reason)."
        case .unsupportedPlatform:
            return "CoreBluetooth is not available on this platform."
        }
    }
}

struct POSBluetoothConfiguration: Sendable {
    let printerServiceUUIDStrings: [String]
    let printerWriteCharacteristicUUIDStrings: [String]
    let printerNameHints: [String]
    let reconnectLimit: Int

    static let `default` = POSBluetoothConfiguration(
        printerServiceUUIDStrings: [
            "18F0",
            "FFF0",
            "FFE0",
            "49535343-FE7D-4AE5-8FA9-9FAFD205E455"
        ],
        printerWriteCharacteristicUUIDStrings: [
            "2AF1",
            "FFF1",
            "FFF2",
            "FFE1",
            "49535343-8841-43F4-A8D4-ECBE34729BB3"
        ],
        printerNameHints: [
            "printer",
            "receipt",
            "thermal",
            "esc",
            "pos",
            "mpt",
            "rp"
        ],
        reconnectLimit: 3
    )
}

enum ThermalReceiptPayloadBuilder {
    private static let lineWidth = 42

    /// Builds an ESC/POS receipt payload that can be sent directly to a compatible thermal printer.
    static func payload(for snapshot: ReceiptSnapshot, opensCashDrawer: Bool = false) -> Data {
        var data = Data()
        data.append(contentsOf: [0x1B, 0x40]) // Initialize printer.

        appendCentered(snapshot.businessName.uppercased(), to: &data, emphasized: true)
        if let address = snapshot.businessAddress {
            appendCentered(address, to: &data)
        }
        if let contactLine = snapshot.contactLine {
            appendCentered(contactLine, to: &data)
        }

        appendLine("", to: &data)
        appendLine(snapshot.receiptNumber, to: &data)
        appendLine(snapshot.dateLine, to: &data)
        appendLine(snapshot.clientName, to: &data)
        if let phone = snapshot.clientPhoneFormatted {
            appendLine(phone, to: &data)
        }
        appendLine(snapshot.petLine, to: &data)
        appendDivider(to: &data)

        for item in snapshot.items {
            appendLine(twoColumn(left: item.name, right: item.priceString), to: &data)
        }

        appendDivider(to: &data)
        data.append(contentsOf: [0x1B, 0x45, 0x01])
        appendLine(twoColumn(left: "TOTAL", right: snapshot.totalString), to: &data)
        data.append(contentsOf: [0x1B, 0x45, 0x00])

        if let payment = snapshot.payment {
            appendLine("", to: &data)
            appendLine(payment.infoLine, to: &data)
            if let referenceLine = payment.referenceLine {
                appendLine(referenceLine, to: &data)
            }
        }

        appendLine("", to: &data)
        appendCentered("Thank you for choosing Pawtrackr.", to: &data)
        appendLine("\n\n", to: &data)

        if opensCashDrawer {
            data.append(contentsOf: [0x1B, 0x70, 0x00, 0x19, 0xFA])
        }
        data.append(contentsOf: [0x1D, 0x56, 0x41, 0x10]) // Partial cut.
        return data
    }

    private static func appendCentered(_ value: String, to data: inout Data, emphasized: Bool = false) {
        data.append(contentsOf: [0x1B, 0x61, 0x01])
        if emphasized {
            data.append(contentsOf: [0x1B, 0x45, 0x01])
        }
        appendLine(value, to: &data)
        if emphasized {
            data.append(contentsOf: [0x1B, 0x45, 0x00])
        }
        data.append(contentsOf: [0x1B, 0x61, 0x00])
    }

    private static func appendDivider(to data: inout Data) {
        appendLine(String(repeating: "-", count: lineWidth), to: &data)
    }

    private static func appendLine(_ value: String, to data: inout Data) {
        let normalized = value
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
        if let lineData = (normalized + "\n").data(using: .ascii, allowLossyConversion: true) {
            data.append(lineData)
        }
    }

    private static func twoColumn(left: String, right: String) -> String {
        let availableLeftWidth = max(1, lineWidth - right.count - 1)
        let leftValue: String
        if left.count > availableLeftWidth {
            let prefixCount = max(1, availableLeftWidth - 1)
            leftValue = String(left.prefix(prefixCount)) + "~"
        } else {
            leftValue = left
        }
        let spaces = max(1, lineWidth - leftValue.count - right.count)
        return leftValue + String(repeating: " ", count: spaces) + right
    }
}

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth

final class BluetoothPeripheralManager: NSObject, @unchecked Sendable {
    static let shared = BluetoothPeripheralManager()

    private let configuration: POSBluetoothConfiguration
    private let workQueue = DispatchQueue(label: "com.pawtrackr.hardware.bluetooth", qos: .utility)
    private var centralManager: CBCentralManager?
    private var shouldScanForPrinters = false
    private var shouldAutoConnectPrinters = true
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var discoveredDescriptors: [UUID: POSPeripheralDescriptor] = [:]
    private var connectedPrinterPeripheral: CBPeripheral?
    private var printerWriteCharacteristic: CBCharacteristic?
    private var reconnectAttemptsByPeripheralID: [UUID: Int] = [:]
    private var pendingConnectionContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var pendingConnectionTimeouts: [UUID: DispatchWorkItem] = [:]

    private lazy var printerServiceUUIDs: [CBUUID] = configuration.printerServiceUUIDStrings.map(CBUUID.init(string:))
    private lazy var printerWriteCharacteristicUUIDs: [CBUUID] = configuration.printerWriteCharacteristicUUIDStrings.map(CBUUID.init(string:))

    init(configuration: POSBluetoothConfiguration = .default) {
        self.configuration = configuration
        super.init()
    }

    /// Starts low-energy printer discovery on the dedicated hardware queue.
    func startPrinterDiscovery(autoConnect: Bool = true) async {
        await withCheckedContinuation { continuation in
            workQueue.async {
                self.shouldScanForPrinters = true
                self.shouldAutoConnectPrinters = autoConnect
                let manager = self.ensureCentralManager()
                if manager.state == .poweredOn {
                    self.beginPrinterScan(manager)
                } else {
                    Logger.bluetoothHardware.info("Bluetooth printer discovery waiting for state: \(self.describe(manager.state), privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    /// Returns the peripherals discovered during the current process lifetime.
    func knownPeripherals() async -> [POSPeripheralDescriptor] {
        await withCheckedContinuation { continuation in
            workQueue.async {
                continuation.resume(returning: self.discoveredDescriptors.values.sorted { $0.name < $1.name })
            }
        }
    }

    /// Connects to a discovered thermal printer and waits until a write characteristic is available.
    func connectThermalPrinter(id: UUID, timeout: TimeInterval = 8) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workQueue.async {
                let manager = self.ensureCentralManager()
                guard manager.state == .poweredOn else {
                    continuation.resume(throwing: self.stateError(for: manager.state))
                    return
                }
                guard let peripheral = self.discoveredPeripherals[id] else {
                    continuation.resume(throwing: PeripheralError.peripheralNotFound(id))
                    return
                }

                if peripheral.state == .connected, self.printerWriteCharacteristic != nil {
                    continuation.resume()
                    return
                }

                self.pendingConnectionContinuations[id] = continuation
                let timeoutItem = DispatchWorkItem { [weak self, weak peripheral] in
                    guard let self else { return }
                    guard let pending = self.pendingConnectionContinuations.removeValue(forKey: id) else { return }
                    self.pendingConnectionTimeouts[id] = nil
                    if let peripheral {
                        self.centralManager?.cancelPeripheralConnection(peripheral)
                    }
                    pending.resume(throwing: PeripheralError.connectionTimedOut)
                }
                self.pendingConnectionTimeouts[id] = timeoutItem
                self.workQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
                peripheral.delegate = self
                manager.connect(peripheral, options: nil)
            }
        }
    }

    /// Sends a raw ESC/POS payload to the connected thermal printer without blocking the UI.
    func transmitThermalReceiptPayload(
        transactionToken: String,
        payload: Data,
        timeout: TimeInterval = 10,
        maxRetries: Int = 2
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workQueue.async {
                do {
                    try self.validatePrinterReady()
                    var lastError: Error?
                    for attempt in 0...maxRetries {
                        do {
                            try self.write(payload: payload, timeout: timeout)
                            Logger.bluetoothHardware.info("Printed physical receipt for transaction \(transactionToken, privacy: .public)")
                            continuation.resume()
                            return
                        } catch {
                            lastError = error
                            Logger.bluetoothHardware.error("Receipt transmit attempt \(attempt + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                            if attempt < maxRetries {
                                Thread.sleep(forTimeInterval: 0.15)
                            }
                        }
                    }
                    throw lastError ?? PeripheralError.transmissionFailed("Unknown write failure.")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureCentralManager() -> CBCentralManager {
        if let centralManager {
            return centralManager
        }
        let manager = CBCentralManager(
            delegate: self,
            queue: workQueue,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        centralManager = manager
        return manager
    }

    private func beginPrinterScan(_ manager: CBCentralManager) {
        guard !manager.isScanning else { return }
        Logger.bluetoothHardware.info("Starting BLE printer discovery")
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func validatePrinterReady() throws {
        guard let manager = centralManager, manager.state == .poweredOn else {
            throw PeripheralError.bluetoothHardwareOffline
        }
        guard let peripheral = connectedPrinterPeripheral, peripheral.state == .connected else {
            throw PeripheralError.printerNotConnected
        }
        guard printerWriteCharacteristic != nil else {
            throw PeripheralError.printerWriteCharacteristicUnavailable
        }
    }

    private func write(payload: Data, timeout: TimeInterval) throws {
        guard !payload.isEmpty else { return }
        guard let peripheral = connectedPrinterPeripheral, let characteristic = printerWriteCharacteristic else {
            throw PeripheralError.printerNotConnected
        }

        let writeType: CBCharacteristicWriteType
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else {
            throw PeripheralError.printerWriteCharacteristicUnavailable
        }

        let maxLength = max(20, peripheral.maximumWriteValueLength(for: writeType))
        let deadline = Date().addingTimeInterval(timeout)
        var offset = 0

        while offset < payload.count {
            if Date() > deadline {
                throw PeripheralError.transmissionTimedOut
            }

            if writeType == .withoutResponse {
                while !peripheral.canSendWriteWithoutResponse {
                    if Date() > deadline {
                        throw PeripheralError.transmissionTimedOut
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }

            let end = min(offset + maxLength, payload.count)
            peripheral.writeValue(payload.subdata(in: offset..<end), for: characteristic, type: writeType)
            offset = end

            if writeType == .withResponse {
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
    }

    private func didFindWritableCharacteristic(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        connectedPrinterPeripheral = peripheral
        printerWriteCharacteristic = characteristic
        reconnectAttemptsByPeripheralID[peripheral.identifier] = 0

        if let timeout = pendingConnectionTimeouts.removeValue(forKey: peripheral.identifier) {
            timeout.cancel()
        }
        if let pending = pendingConnectionContinuations.removeValue(forKey: peripheral.identifier) {
            pending.resume()
        }

        Logger.bluetoothHardware.info("Connected thermal printer \(peripheral.name ?? "Unnamed", privacy: .public)")
    }

    private func failPendingConnection(for peripheral: CBPeripheral, error: Error) {
        if let timeout = pendingConnectionTimeouts.removeValue(forKey: peripheral.identifier) {
            timeout.cancel()
        }
        if let pending = pendingConnectionContinuations.removeValue(forKey: peripheral.identifier) {
            pending.resume(throwing: error)
        }
    }

    private func reconnectIfNeeded(_ peripheral: CBPeripheral) {
        guard shouldAutoConnectPrinters else { return }
        let attempts = reconnectAttemptsByPeripheralID[peripheral.identifier, default: 0]
        guard attempts < configuration.reconnectLimit else { return }
        reconnectAttemptsByPeripheralID[peripheral.identifier] = attempts + 1
        centralManager?.connect(peripheral, options: nil)
    }

    private func descriptor(for peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) -> POSPeripheralDescriptor {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? "Unknown Peripheral"
        return POSPeripheralDescriptor(
            id: peripheral.identifier,
            name: name,
            kind: inferKind(name: name, advertisementData: advertisementData),
            rssi: rssi.intValue
        )
    }

    private func inferKind(name: String, advertisementData: [String: Any]) -> POSPeripheralDescriptor.Kind {
        let lowercasedName = name.lowercased()
        if configuration.printerNameHints.contains(where: { lowercasedName.contains($0) }) {
            return .thermalPrinter
        }

        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        if serviceUUIDs.contains(where: { printerServiceUUIDs.contains($0) }) {
            return .thermalPrinter
        }

        if lowercasedName.contains("cash") || lowercasedName.contains("drawer") {
            return .cashDrawer
        }
        if lowercasedName.contains("rfid") || lowercasedName.contains("scanner") {
            return .rfidScanner
        }
        return .unknown
    }

    private func stateError(for state: CBManagerState) -> PeripheralError {
        state == .poweredOff ? .bluetoothHardwareOffline : .bluetoothUnavailable(describe(state))
    }

    private func describe(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unrecognized"
        }
    }
}

extension BluetoothPeripheralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Logger.bluetoothHardware.info("Bluetooth state changed: \(self.describe(central.state), privacy: .public)")
        if central.state == .poweredOn, shouldScanForPrinters {
            beginPrinterScan(central)
        } else if central.state != .poweredOn {
            connectedPrinterPeripheral = nil
            printerWriteCharacteristic = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let descriptor = descriptor(for: peripheral, advertisementData: advertisementData, rssi: RSSI)
        discoveredPeripherals[peripheral.identifier] = peripheral
        discoveredDescriptors[peripheral.identifier] = descriptor

        guard descriptor.kind == .thermalPrinter else { return }
        Logger.bluetoothHardware.info("Discovered thermal printer candidate \(descriptor.name, privacy: .public)")

        if shouldAutoConnectPrinters, connectedPrinterPeripheral == nil {
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(printerServiceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let connectionError = error ?? PeripheralError.transmissionFailed("Failed to connect.")
        failPendingConnection(for: peripheral, error: connectionError)
        Logger.bluetoothHardware.error("Failed to connect printer \(peripheral.name ?? "Unnamed", privacy: .public): \(connectionError.localizedDescription, privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == connectedPrinterPeripheral?.identifier {
            connectedPrinterPeripheral = nil
            printerWriteCharacteristic = nil
        }
        if let error {
            Logger.bluetoothHardware.error("Printer disconnected: \(error.localizedDescription, privacy: .public)")
        } else {
            Logger.bluetoothHardware.info("Printer disconnected cleanly")
        }
        reconnectIfNeeded(peripheral)
    }
}

extension BluetoothPeripheralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            failPendingConnection(for: peripheral, error: error)
            Logger.bluetoothHardware.error("Printer service discovery failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let services = peripheral.services ?? []
        if services.isEmpty {
            failPendingConnection(for: peripheral, error: PeripheralError.printerWriteCharacteristicUnavailable)
            return
        }

        for service in services {
            peripheral.discoverCharacteristics(printerWriteCharacteristicUUIDs, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            failPendingConnection(for: peripheral, error: error)
            Logger.bluetoothHardware.error("Printer characteristic discovery failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let writable = (service.characteristics ?? []).first { characteristic in
            characteristic.properties.contains(.writeWithoutResponse) || characteristic.properties.contains(.write)
        }

        if let writable {
            didFindWritableCharacteristic(writable, on: peripheral)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Logger.bluetoothHardware.debug("Printer write-without-response window reopened")
    }
}

#else

final class BluetoothPeripheralManager: @unchecked Sendable {
    static let shared = BluetoothPeripheralManager()

    func startPrinterDiscovery(autoConnect: Bool = true) async {}

    func knownPeripherals() async -> [POSPeripheralDescriptor] { [] }

    func connectThermalPrinter(id: UUID, timeout: TimeInterval = 8) async throws {
        throw PeripheralError.unsupportedPlatform
    }

    func transmitThermalReceiptPayload(
        transactionToken: String,
        payload: Data,
        timeout: TimeInterval = 10,
        maxRetries: Int = 2
    ) async throws {
        throw PeripheralError.unsupportedPlatform
    }
}

#endif

private extension Logger {
    static let bluetoothHardware = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "BluetoothHardware")
}
