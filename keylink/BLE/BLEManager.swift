import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false
    @Published var statusMessage = "Scanning..."
    @Published var lastReaderEvent: String?
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var cmdChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    
    let serviceUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000001")
    let cmdUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000002")
    let statusUUID = CBUUID(string: "a0000000-0000-0000-0000-000000000003")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
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
        guard let data = characteristic.value,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        DispatchQueue.main.async {
            if let status = json["status"] as? String {
                self.statusMessage = status
            }
            if let msg = json["msg"] as? String, msg == "auth_received" {
                self.lastReaderEvent = "🔓 Reader authenticated!"
            }
        }
    }
    
    func sendCommand(_ dict: [String: Any]) {
        guard let char = cmdChar, let peripheral = peripheral else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        peripheral.writeValue(data, for: char, type: .withResponse)
    }
    
    func loadCard(uid: String, atqa: [UInt8] = [0x00, 0x04], sak: UInt8 = 0x08, sectors: [[UInt8]]? = nil) {
        var payload: [String: Any] = [
            "cmd": "load_card",
            "uid": uid,
            "atqa": atqa,
            "sak": sak
        ]
        if let sectors = sectors {
            payload["sectors"] = sectors
        }
        sendCommand(payload)
    }
    
    func startEmulate(duration: Int = 30) {
        sendCommand(["cmd": "emulate", "duration": duration * 1000])
    }
    
    func stopEmulate() {
        sendCommand(["cmd": "stop"])
    }
}
