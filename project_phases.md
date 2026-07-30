# KeyLink: Project Phases

Based on the architecture and workflow of the KeyLink project, here are the defined phases from initial recon to the final hardware/software integration, as well as future updates (v2.0).

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

## Phase 3: ESP32 Firmware Development
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
- Implement `CardImportManager` to parse Proxmark3 JSON dumps (`hf mf dump -k ...`).

## Phase 5: Proxmark3 to Bridge Data Flow (The Full Loop)
**Goal:** Perform the end-to-end extraction and emulation process.
1. Dump the card with Proxmark3 (`hf mf dump`).
2. Convert the raw `.bin` dump to a structured JSON format (UID, ATQA, SAK, sectors) using a Python script.
3. AirDrop or copy the JSON to the iPhone.
4. Import the JSON into the KeyLink iOS app.
5. Save the card to the local library.

## Phase 6: Real-World Testing
**Goal:** Test the proxy device on an actual reader (e.g., gym door).
1. Power on the ESP32 proxy bridge.
2. Open the KeyLink iOS app and let it auto-connect.
3. Select the imported card and tap "Start Emulation".
4. Hold the ESP32 bridge to the NFC reader.
5. If the reader is UID-only, the door will open. If it checks sectors, the fake zero-auth might work, or it will reject the card.

---

## Future Roadmap (v2.0)
**Goal:** Address limitations of v1.0 and expand compatibility.
- **Real Crypto1 Authentication:** Instead of sending fake zeros, implement the full MIFARE Classic Crypto1 state machine for strict readers.
- **125 kHz Support:** Add a T5577 chip or a custom TX coil to support older RFID badges (e.g., HID Prox).
- **Auto JSON Import:** Improve the iOS app to handle raw Proxmark3 files natively without the intermediary Python script.
- **NFC Driver for iOS 18+ (TrollStore):** Continue research into direct iPhone NFC emulation (TrollNFC equivalent) as a secondary, exploit-based path.
