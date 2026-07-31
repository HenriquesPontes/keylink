# KeyCard: Project Phases

Based on the architecture and workflow of the KeyCard project, here are the defined phases from initial recon to the final hardware/software integration, as well as future updates (v2.0).

---

## Phase 0: Reconnaissance & Feasibility
**Goal:** Determine compatibility of the target NFC card before investing in hardware.
- Use the **NFC Tools** app on an iPhone to scan the target card.
- If it beeps (13.56 MHz), proceed. If not (125 kHz HID Prox / EM4100), different hardware is needed.
- Use Proxmark3 (`hf search`) to identify the chip type (e.g., MIFARE Classic 1K, MIFARE Ultralight, NTAG).
- If MIFARE Classic, capture the UID (many readers only check UID, making emulation much easier).

## Phase 1: Hardware Acquisition (BOM)
**Goal:** Order the necessary components for the BLE-to-NFC proxy bridge.
- **Microcontroller:** ESP32-S3-DevKitC-1 (Provides BLE 5.0 and GPIOs).
- **NFC Frontend:** PN532 module (Required for its `TgInitAsTarget` card emulation mode).
- **Power:** 3.7V 500mAh LiPo battery + TP4056 USB-C charging module.
- **Misc:** 3.3V to 5V Level Shifter (optional), jumper wires, and a 3D-printed enclosure.
- *Estimated Cost:* ~$22 USD.

## Phase 2: Hardware Wiring & Assembly
**Goal:** Connect the components to build the proxy device.
- Configure the PN532 switch to **HSU (UART)** mode.
- Wire the PN532 (VCC, GND, TXD, RXD) to the ESP32 (3.3V, GND, GPIO17, GPIO18).
- Wire the LiPo battery and TP4056 charging module.

## Phase 3: ESP32 Firmware Development ✅ (Completed)
**Goal:** Write and flash the firmware to act as a BLE peripheral and NFC emulator.
- Use Arduino IDE with the `elechouse/PN532` and `ArduinoJson` libraries.
- Set up a BLE Server with specific UUIDs for Commands and Status notifications.
- Parse incoming JSON payloads over BLE (Commands: `load_card`, `emulate`, `stop`).
- Use the PN532 `tgInitAsTarget` function to broadcast the UID and emulate a MIFARE Classic card.
- Provide fake authentication responses (zeros) to sector reads to trick basic readers.

## Phase 4: iOS App Development (Software Bridge) ✅ (Completed)
**Goal:** Build the SwiftUI app to store cards and control the ESP32 via BLE.
- Request `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
- Build the `BLEManager` to connect to the ESP32 and send JSON commands.
- Implement the SwiftData `Card` model.
- Build the UI: `CardLibraryView` (Saved cards list), `CardImportView` (JSON File/Clipboard parsing), and `EmulationView` (Timer and BLE status).
- Implement `CardImportManager` to natively parse raw `.bin` Proxmark3 dumps (`hf mf dump -k ...`).

## Phase 5: Proxmark3 to Bridge Data Flow (The Full Loop) ✅ (Completed)
**Goal:** Perform the end-to-end extraction and emulation process.
1. Dump the card with Proxmark3 (`hf mf dump`).
2. AirDrop or copy the raw `.bin` dump directly to the iPhone.
3. Import the `.bin` into the KeyCard iOS app.
4. Save the card to the local library.

## Phase 6: Real-World Testing
**Goal:** Test the proxy device on an actual reader (e.g., gym door).
1. Power on the ESP32 proxy bridge.
2. Open the KeyCard iOS app and let it auto-connect.
3. Select the imported card and tap "Start Emulation".
4. Hold the ESP32 bridge to the NFC reader.
5. If the reader is UID-only, the door will open. If it checks sectors, the hardware Crypto1 module and keys loaded onto the bridge will negotiate access.

---

## Future Roadmap (v2.0) ✅ (Completed)
**Goal:** Address limitations of v1.0 and expand compatibility.
- **Real Crypto1 Authentication:** ✅ The ESP32 firmware now includes the `crapto1` engine to handle the MIFARE Classic Crypto1 state machine locally for strict readers.
- **Nested Authentication:** ✅ Firmware fully supports on-the-fly decryption of nested 0x60/0x61 commands for encrypted sectors.
- **Persistent Card Library:** ✅ Swapped UserDefaults for SwiftData and enabled iCloud sync for reliable, schema-driven data persistence.
- **Sector Key Management:** ✅ Implemented `CardDetailView` for viewing/editing A/B keys per sector.
- **7-Byte UID Constraint:** ✅ Implemented fallback protocol to map 7-byte UIDs (Cascade 2) into the 4-byte PN532 hardware constraint alongside UI warnings.

---

## Future Roadmap (v3.0) & Robustness (v1.1) ✅ (Completed)
**Goal:** Improve reliability and expand protocol support.
- **Robustness (v1.1):** ✅ PN532 auto-retry on timeout, battery level reporting over BLE, and configurable emulation duration.
- **Background BLE Reconnection:** ✅ Ensure the app stays connected to the bridge in your pocket.
- **Multi-Protocol Expansion (v3.0):** ✅ Added complete support for MIFARE Ultralight / NTAG emulation.
- **125 kHz Support:** ✅ Software integration and firmware PWM carrier generation implemented for HID Prox badges.
- **DESFire Light (UID-only):** ✅ Added support for importing DESFire Light targets and instructing the PN532 to initialize ISO/IEC 14443-4 target mode.
- **Ecosystem Integration:** ⏭️ Skipped Apple Watch companion app and Lock Screen widgets.

---

## Future Roadmap (v4.0)
With the core software and multi-protocol logic complete, the following features are prime targets for v4.0:
- **Firmware OTA Updates:** ✅ Built a robust mechanism using `Update.h` and iOS `URLSession` to push new firmware versions over a local ESP32 Wi-Fi AP.
- **Security Enhancements:** ✅ Implemented `BLESecurity` with MITM protection and a static passkey, plus Encrypted GATT characteristics to prevent plaintext key transmission over the air.
- **Automated Testing:** ✅ Wrote and successfully passed native XCTest suites for the `CardImportManager` to confidently validate Proxmark3 dump parsing edge-cases.
- **Custom Hardware Design (PCB):** ✅ Drafted a schematic and PCB layout netlist for the bridge components to create a tiny, 3D-printable, wearable form factor.

---

## Next Immediate Steps

The KeyCard software stack is functionally complete. The optimal next steps are:

1. **Hardware Assembly & Real-World Testing:** Procure the ESP32-S3 and PN532, wire them via UART, flash the `keycard_bridge.ino` firmware, and test against a physical door reader.
2. **Select a v4.0 Feature:** Decide on security, OTA, testing, or custom hardware to focus on next.
