import Foundation
import CoreBluetooth
import Combine
import UIKit
import CryptoKit

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // 32-byte Static PSK for AES-256-GCM
    let psk = SymmetricKey(data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 
                                       0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                                       0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
                                       0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20]))
    @Published var isConnected = false
    @Published var statusMessage = "Scanning..."
    @Published var lastReaderEvent: String?
    @Published var batteryLevel: Int?
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cmdChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    
    let serviceUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000001")
    let cmdUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000002")
    let statusUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000003")
    
    override init() {
        super.init()
        let options: [String: Any] = [CBCentralManagerOptionRestoreIdentifierKey: "keycard-ble-restore"]
        centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if peripheral == nil {
                central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for restored in restoredPeripherals {
                self.peripheral = restored
                restored.delegate = self
                if restored.state == .disconnected {
                    central.connect(restored, options: nil)
                } else if restored.state == .connected {
                    isConnected = true
                    statusMessage = "Connected"
                    restored.discoverServices([serviceUUID])
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        central.stopScan()
        central.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusMessage = "Connected"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "Disconnected. Reconnecting..."
        batteryLevel = nil
        // Automatically attempt to reconnect in the background
        central.connect(peripheral, options: nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([cmdUUID, statusUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == cmdUUID { cmdChar = char }
            if char.uuid == statusUUID {
                statusChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let combinedData = characteristic.value else { return }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: psk)
            
            guard let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                if let status = json["status"] as? String {
                    self.statusMessage = status
                }
                if let battery = json["battery"] as? Int {
                    self.batteryLevel = battery
                }
                if let msg = json["msg"] as? String, msg == "auth_received" {
                    self.lastReaderEvent = "🔓 Reader authenticated!"
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        } catch {
            print("Failed to decrypt notification: \(error)")
        }
    }
    
    func sendCommand(_ dict: [String: Any]) {
        guard let char = cmdChar, let peripheral = peripheral else { return }
        guard let plaintext = try? JSONSerialization.data(withJSONObject: dict) else { return }
        
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: psk)
            guard let combinedData = sealedBox.combined else { return }
            peripheral.writeValue(combinedData, for: char, type: .withResponse)
        } catch {
            print("Failed to encrypt command: \(error)")
        }
    }
    
    func loadCard(_ card: Card) {
        var payload: [String: Any] = [
            "cmd": "load_card",
            "type": card.type.rawValue,
            "uid": card.uid
        ]
        
        if card.type == .mifareClassic {
            payload["atqa"] = card.atqa
            payload["sak"] = card.sak
            if let sectors = card.sectors {
                payload["sectors"] = sectors
            }
        } else if card.type == .mifareUltralight {
            if let pages = card.pages {
                payload["pages"] = pages
            }
        } else if card.type == .desfireLight {
            // DESFire Light is UID-only in our implementation for now, so no payload addition
        } else if card.type == .desfire {
            if let desfireData = card.desfireData {
                payload["desfireData"] = desfireData
            }
        }
        
        sendCommand(payload)
    }
    
    func startEmulate(card: Card, duration: Int = 30) {
        let cmdName = card.type == .hidProx26 ? "emulate_125" : "emulate"
        sendCommand(["cmd": cmdName, "duration": duration * 1000])
    }
    
    func stopEmulate() {
        sendCommand(["cmd": "stop"])
    }
    
    func enterOTA() {
        sendCommand(["cmd": "enter_ota"])
    }
}
