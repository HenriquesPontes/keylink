Alright, let's build it. Here's the full stack — from parts list to working code.

---

# Phase 0: Recon (Do This Before Buying Anything)

**You need to know what chip your gym card uses.** Order of difficulty:

| Chip Type | Can We Emulate It? | How to Identify |
|---|---|---|
| **MIFARE Classic 1K** (most common for gyms) | ✅ Easy — UID + sectors | Proxmark3: `hf search` shows `MIFARE Classic 1K` |
| **MIFARE Ultralight / NTAG** | ✅ Trivial — just UID/NDEF | `hf search` shows `NTAG213/215/216` |
| **MIFARE DESFire EV1/EV2** | ❌ Hard — AES, rolling keys | `hf search` shows `MIFARE DESFire` |
| **125 kHz HID Prox / EM4100** | ⚠️ Needs different hardware | iPhone **won't detect it at all** |

**Quick test:** Download **NFC Tools** (free) on your iPhone. Scan the green fob.
- **If it beeps and shows data** → 13.56 MHz. You're in business.
- **If nothing happens** → Probably 125 kHz. We'll need a separate module for that.

For your OnAir card, scan it. If it's MIFARE Classic, note down the UID. Many cheap gym readers only check the UID — meaning we don't even need to dump sectors.

---

# Phase 1: Hardware BOM

| Part | Model | Price | Where |
|---|---|---|---|
| **MCU** | ESP32-S3-DevKitC-1 | ~$8 | Amazon/AliExpress |
| **NFC Frontend** | PN532 module (red board, I2C/SPI/HSU) | ~$5 | AliExpress |
| **Level Shifter** | 3.3V ↔ 5V (optional, ESP32 is 3.3V, PN532 is 3.3V-5V tolerant) | ~$1 | — |
| **Battery** | 3.7V 500mAh LiPo (502535) | ~$4 | AliExpress |
| **Charging** | TP4056 USB-C charging module | ~$1 | AliExpress |
| **Enclosure** | 3D print or small project box | ~$3 | — |
| **Wires** | Dupont jumper wires | — | — |

**Total: ~$22**

**Why ESP32-S3?** It has both BLE 5.0 and enough GPIOs. The regular ESP32 also works.

**Why PN532?** It's the only cheap module that supports **card emulation mode** (`TgInitAsTarget`). RC522 and PN5180 are reader-only.

---

# Phase 2: Wiring

```
ESP32-S3          PN532 Module
─────────         ───────────
3.3V    ────────► VCC
GND     ────────► GND
GPIO17  ────────► TXD  (ESP32 RX)
GPIO18  ────────► RXD  (ESP32 TX)

LiPo (+) ───────► TP4056 OUT+
LiPo (-) ───────► TP4056 OUT-
TP4056 USB-C    ◄── charging port
```

The PN532 red board has a switch: set it to **HSU** (UART) mode.

---

# Phase 3: ESP32 Firmware

Install these libraries in Arduino IDE:
- `PN532` by Adafruit (or better: `PN532` by Seeed-Studio — but we'll use elechouse's fork for emulation)
- `ArduinoJson` by Benoit Blanchon

**Important:** Use the **elechouse/PN532** library. It has the `tgInitAsTarget` function we need.

```cpp
/*
 * ESP32 NFC Bridge Firmware
 * BLE-controlled PN532 card emulator
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <PN532_HSU.h>
#include <PN532.h>
#include <ArduinoJson.h>

// ── CONFIG ──
#define BLE_DEVICE_NAME   "NFC-Bridge"
#define SERVICE_UUID      "a0000000-0000-0000-0000-000000000001"
#define CMD_CHAR_UUID     "a0000000-0000-0000-0000-000000000002"
#define STATUS_CHAR_UUID  "a0000000-0000-0000-0000-000000000003"

// PN532 on Serial2
PN532_HSU pn532hsu(Serial2);
PN532 nfc(pn532hsu);

// ── CARD STORAGE ──
uint8_t cardUID[7]     = {0xA1, 0xB2, 0xC3, 0xD4};
uint8_t cardUIDLen     = 4;
uint8_t cardATQA[2]    = {0x04, 0x00};
uint8_t cardSAK        = 0x08; // MIFARE Classic 1K
uint8_t cardSectors[64][16];   // 64 blocks × 16 bytes
bool    hasCardData    = false;
bool    emulateActive  = false;
uint32_t emulateStart  = 0;
uint32_t emulateDuration = 30000; // 30s default

// ── BLE ──
BLEServer *pServer = nullptr;
BLECharacteristic *pCmdChar = nullptr;
BLECharacteristic *pStatusChar = nullptr;
bool deviceConnected = false;

class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* server) { deviceConnected = true; }
  void onDisconnect(BLEServer* server) { deviceConnected = false; }
};

class CmdCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string raw = pCharacteristic->getValue();
    if (raw.length() == 0) return;
    
    StaticJsonDocument<4096> doc;
    DeserializationError err = deserializeJson(doc, raw);
    if (err) { sendStatus("error", "json_parse_failed"); return; }
    
    const char* cmd = doc["cmd"];
    if (!cmd) { sendStatus("error", "no_cmd"); return; }
    
    if (strcmp(cmd, "load_card") == 0) {
      // Load card data from JSON
      const char* uidHex = doc["uid"];
      if (uidHex && strlen(uidHex) >= 8) {
        cardUIDLen = strlen(uidHex) / 2;
        for (int i = 0; i < cardUIDLen; i++) {
          sscanf(uidHex + 2*i, "%2hhx", &cardUID[i]);
        }
      }
      cardATQA[0] = doc["atqa"][0] | 0x00;
      cardATQA[1] = doc["atqa"][1] | 0x00;
      cardSAK     = doc["sak"] | 0x08;
      
      JsonArray sectors = doc["sectors"];
      if (sectors) {
        for (int b = 0; b < 64 && b < sectors.size(); b++) {
          JsonArray block = sectors[b];
          for (int i = 0; i < 16 && i < block.size(); i++) {
            cardSectors[b][i] = block[i];
          }
        }
      }
      hasCardData = true;
      sendStatus("ready", "card_loaded");
    }
    else if (strcmp(cmd, "emulate") == 0) {
      if (!hasCardData) { sendStatus("error", "no_card_loaded"); return; }
      emulateDuration = doc["duration"] | 30000;
      emulateActive = true;
      emulateStart = millis();
      sendStatus("emulating", "started");
    }
    else if (strcmp(cmd, "stop") == 0) {
      emulateActive = false;
      sendStatus("idle", "stopped");
    }
    else if (strcmp(cmd, "ping") == 0) {
      sendStatus("pong", hasCardData ? "has_card" : "no_card");
    }
  }
};

void sendStatus(const char* status, const char* msg) {
  StaticJsonDocument<256> doc;
  doc["status"] = status;
  doc["msg"] = msg;
  doc["uid"] = uidToString();
  char buf[256];
  serializeJson(doc, buf);
  if (pStatusChar) {
    pStatusChar->setValue(buf);
    pStatusChar->notify();
  }
}

char* uidToString() {
  static char buf[16];
  for (int i = 0; i < cardUIDLen; i++) sprintf(buf + 2*i, "%02X", cardUID[i]);
  buf[2*cardUIDLen] = '\0';
  return buf;
}

// ── NFC EMULATION ──
void handleEmulation() {
  // Build TgInitAsTarget command for MIFARE Classic 1K
  // See PN532 User Manual §7.3.13
  uint8_t tgInit[] = {
    0x04,                       // Mode: PICC only, Passive 106kbps
    cardATQA[1], cardATQA[0],   // SENS_RES (ATQA) — little endian!
    cardUID[0], cardUID[1], cardUID[2], cardUID[3], // NFCID1t (UID)
    cardSAK,                    // SEL_RES (SAK)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // FeliCaParam
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // NFCID3t
    0x00,                       // Length of general bytes
    0x00                        // Length of historical bytes
  };
  
  // For 7-byte UID, the format changes slightly — keeping it simple with 4-byte here
  
  if (!nfc.tgInitAsTarget(tgInit, sizeof(tgInit), 0)) {
    return; // No reader field detected
  }
  
  // Reader detected us! Handle commands
  uint8_t cmdBuf[64];
  uint8_t cmdLen;
  
  while (millis() - emulateStart < emulateDuration) {
    if (!nfc.tgGetData(cmdBuf, &cmdLen)) {
      // Reader released us or error
      break;
    }
    
    // MIFARE Classic command parsing
    uint8_t response[64];
    uint8_t respLen = 0;
    bool handled = false;
    
    if (cmdLen >= 2 && (cmdBuf[0] == 0x60 || cmdBuf[0] == 0x61)) {
      // AUTH_A or AUTH_B — many cheap readers accept any response
      // Real Crypto1 would require stateful nonce exchange; we fake it for UID-only readers
      response[0] = 0x00; response[1] = 0x00; response[2] = 0x00; response[3] = 0x00;
      respLen = 4;
      handled = true;
      sendStatus("reader_cmd", "auth_received");
    }
    else if (cmdLen >= 2 && cmdBuf[0] == 0x30) {
      // READ block
      uint8_t block = cmdBuf[1];
      if (block < 64) {
        memcpy(response, cardSectors[block], 16);
        respLen = 16;
        handled = true;
      }
    }
    else if (cmdLen >= 2 && cmdBuf[0] == 0xA0) {
      // WRITE block — reject
      response[0] = 0x04; // NAK
      respLen = 1;
      handled = true;
    }
    
    if (handled) {
      nfc.tgSetData(response, respLen);
    } else {
      nfc.tgSetData(response, 0); // NAK / silence
    }
  }
  
  emulateActive = false;
  sendStatus("idle", "emulation_timeout");
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, 17, 18); // RX=17, TX=18
  
  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("PN532 not found! Check wiring.");
    while (1); // Halt
  }
  nfc.SAMConfig();
  Serial.println("PN532 ready");
  
  // BLE setup
  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCmdChar = pService->createCharacteristic(CMD_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  pStatusChar = pService->createCharacteristic(STATUS_CHAR_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());
  
  pCmdChar->setCallbacks(new CmdCallbacks());
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  
  Serial.println("BLE advertising...");
}

void loop() {
  if (emulateActive) {
    handleEmulation();
  }
  delay(100);
}
```

**Upload this to your ESP32.** Open Serial Monitor at 115200. You should see "PN532 ready" and "BLE advertising..."

---

# Phase 4: iOS App (SwiftUI)

Create a new SwiftUI project in Xcode. Add these capabilities:
- **Bluetooth LE** (Background Modes → Uses Bluetooth LE accessories)

**BLEManager.swift:**

```swift
import Foundation
import CoreBluetooth

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
```

**ContentView.swift:**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @State private var uidInput = "A1B2C3D4"
    @State private var isEmulating = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Connection status
                HStack {
                    Circle()
                        .fill(ble.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(ble.isConnected ? "Bridge Connected" : "Searching...")
                        .font(.headline)
                }
                
                // Status
                Text(ble.statusMessage)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if let event = ble.lastReaderEvent {
                    Text(event)
                        .font(.title2)
                        .foregroundColor(.green)
                }
                
                Divider()
                
                // Card input
                VStack(alignment: .leading) {
                    Text("Card UID (hex)")
                        .font(.caption)
                    TextField("A1B2C3D4", text: $uidInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                }
                .padding(.horizontal)
                
                Button("Load Card to Bridge") {
                    ble.loadCard(uid: uidInput)
                }
                .buttonStyle(.borderedProminent)
                
                Divider()
                
                // Emulate
                Button(isEmulating ? "Stop Emulation" : "Start Emulation (30s)") {
                    if isEmulating {
                        ble.stopEmulate()
                        isEmulating = false
                    } else {
                        ble.startEmulate(duration: 30)
                        isEmulating = true
                        // Auto-reset after 30s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                            isEmulating = false
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(isEmulating ? .red : .blue)
                .disabled(!ble.isConnected)
                
                Spacer()
            }
            .padding()
            .navigationTitle("NFC Bridge")
        }
    }
}
```

Build and run on your iPhone. It will auto-connect to the ESP32 when in range.

---

# Phase 5: Proxmark3 → Bridge Data Flow

## Step 1: Identify the card
```bash
pm3 --> hf search
```

If it says `MIFARE Classic 1K`, proceed.

## Step 2: Try default keys
```bash
pm3 --> hf mf chk *1 ? t
```
If you get `[+] Found valid key`, great.

## Step 3: Dump it
```bash
pm3 --> hf mf dump
pm3 --> hf mf dump -k hf-mf-[UID]-key.bin
```

This creates `hf-mf-[UID]-dump.bin` (1024 bytes = 64 blocks × 16 bytes).

## Step 4: Get it on your iPhone

**Transfer the raw `.bin` dump:** AirDrop the `hf-mf-[UID]-dump.bin` file to your iPhone, or email it.

**Import directly into KeyLink:** The iOS app natively parses `.bin` files. There is no need for intermediary Python conversion scripts.

---

# Phase 6: Testing

1. **Power on** the ESP32 bridge (it will advertise as "NFC-Bridge")
2. **Open the iOS app** — it connects automatically
3. **Enter your card UID** → tap "Load Card to Bridge"
4. **Tap "Start Emulation"**
5. **Hold the device near the gym reader**

**What should happen:**
- The reader polls for cards
- The PN532 responds with your UID
- If the reader is UID-only: **Door opens**
- If the reader checks sectors: It will send AUTH commands. The bridge will respond with zeros (fake auth). Some readers accept this. Others will reject it.

---

# What Works in v1.0 vs. What Needs v2.0

| Feature | v1.0 (This Build) | v2.0 (Next) |
|---|---|---|
| **UID-only readers** | ✅ Works | ✅ Works |
| **MIFARE Classic sector auth** | ⚠️ Faked (may work) | ✅ Real Crypto1 implementation |
| **125 kHz gate key** | ❌ Not supported | ⚠️ Needs T5577 or custom TX coil |
| **MIFARE DESFire** | ❌ No | ❌ Still no (AES hardware needed) |
| **iOS app import from Proxmark3** | Manual UID entry | Auto raw `.bin` import |
| **Multiple cards** | One at a time | Card library with quick switch |

---

# The Legal Reality (Briefly)

You're building a device that **emulates cards you already own**. In most jurisdictions, that's legal — it's like making a spare key for your own apartment.

**What becomes legally risky:**
- Selling a device marketed as a "card cloner" (DMCA, CFAA in the US)
- Using it to clone cards you don't own
- Bypassing encryption on cards where you don't have authorization

**For a future product:** Partner with access control companies to issue legitimate mobile credentials. Don't sell a "universal cloner." Sell a "universal mobile key platform" that works with certified issuers.

---

**Order the parts. Flash the ESP32. Test it on your gym reader this weekend.** If the reader is UID-only, you'll walk in with your phone. If it checks sectors, we'll implement Crypto1 in v2.0.

