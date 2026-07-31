import SwiftUI
import CoreBluetooth

struct HardwareSettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        Form {
            Section(header: Text("Status")) {
                HStack {
                    Text("Connection")
                    Spacer()
                    Text(bleManager.statusMessage)
                        .foregroundColor(bleManager.isConnected ? .green : .secondary)
                }
                
                if let battery = bleManager.batteryLevel {
                    HStack {
                        Text("Battery")
                        Spacer()
                        Text("\(battery)%")
                            .foregroundColor(battery > 20 ? .green : .red)
                    }
                }
                
                if let lastEvent = bleManager.lastReaderEvent {
                    HStack {
                        Text("Last Event")
                        Spacer()
                        Text(lastEvent)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section(header: Text("Actions"), footer: Text("Firmware OTA mode restarts the bridge into a mode ready to receive firmware updates over WiFi.")) {
                Button(role: .destructive) {
                    bleManager.enterOTA()
                } label: {
                    Text("Enter Firmware OTA Mode")
                }
                .disabled(!bleManager.isConnected)
            }
            
            Section(header: Text("About KeyCard Bridge")) {
                Text("The KeyCard Bridge is a custom ESP32 + PN532 hardware accessory that enables powerful long-range NFC emulation and reading capabilities not natively supported by iPhones.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Hardware Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    HardwareSettingsView()
        .environmentObject(BLEManager())
}
