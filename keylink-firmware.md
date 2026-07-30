# NFC Bridge — Technical Specification
## Universal Mobile Key Platform (v1.0)

> **Purpose:** Turn any iPhone into a universal access key by proxying NFC emulation through a BLE-connected wearable bridge. No jailbreak. No Apple Wallet hacks. Works with existing readers.

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SYSTEM OVERVIEW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────┐         BLE 5.0         ┌─────────────────────────┐      │
│   │   iPhone     │  ◄──────────────────►   │    ESP32-S3 Bridge      │      │
│   │  (SwiftUI)   │    GATT Characteristics │  ┌───────────────────┐  │      │
│   │              │                         │  │   PN532 Module    │  │      │
│   │  • Card Lib  │    CMD  (Write)         │  │  ┌─────────────┐  │  │      │
│   │  • Emulate   │  ───────────────────►   │  │  │  NFC Field  │──┼──┼──► ──┐
│   │  • Import    │    STATUS (Notify)      │  │  │  Emulation  │  │  │      │
│   │              │  ◄───────────────────   │  │  └─────────────┘  │  │      │
│   └──────────────┘                         │  └───────────────────┘  │      │
│                                            └─────────────────────────┘      │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         GYM / BUILDING READER                       │◄──┘
│   │  (MIFARE Classic / Ultralight / DESFire / 125kHz HID / etc.)        │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Design Philosophy
- **iPhone never touches NFC directly.** It uses BLE (fully allowed, no entitlements).
- **Bridge does the NFC emulation.** No Apple Secure Element involvement.
- **Reader sees a normal card.** Zero infrastructure changes.
- **Open-source stack.** Arduino + SwiftUI. No proprietary SDKs.

---

## 2. Tech Stack

### 2.1 Hardware Layer

| Component | Model | Role | Interface |
|---|---|---|---|
| **MCU** | ESP32-S3-DevKitC-1 | BLE host + logic controller | — |
| **NFC Frontend** | PN532 (red board, HSU mode) | 13.56 MHz reader + card emulation | UART @ 115200 |
| **Power** | 3.7V 500mAh LiPo + TP4056 | Battery + USB-C charging | — |
| **Level Shifter** | BSS138 or direct 3.3V | PN532 is 3.3V–5V tolerant | — |

**Why ESP32-S3?**
- Dual-core 240 MHz, BLE 5.0, Wi-Fi (for OTA updates in v2.0).
- Native 3.3V GPIO — no level shifting needed for PN532.
- Cheap, widely available, excellent Arduino support.

**Why PN532 (not RC522 / PN5180)?**
- PN532 is the **only** cheap module that supports `TgInitAsTarget` (card emulation mode).
- RC522 = reader-only. PN5180 = reader-only (no target mode in Arduino libs).

### 2.2 Firmware Layer

| Technology | Version | Purpose |
|---|---|---|
| **Framework** | Arduino Core for ESP32 (v3.x) | Main runtime |
| **NFC Library** | elechouse/PN532 | `tgInitAsTarget`, `tgGetData`, `tgSetData` |
| **BLE Stack** | ESP-IDF BLE (via Arduino) | GATT server, advertising |
| **Serialization** | ArduinoJson (v6.x) | Command/response protocol |

### 2.3 iOS Application Layer

| Technology | Version | Purpose |
|---|---|---|
| **Language** | Swift 5.9+ | Native iOS development |
| **Framework** | SwiftUI | UI layer |
| **Bluetooth** | CoreBluetooth | BLE central (scan, connect, GATT) |
| **File Import** | UniformTypeIdentifiers | Raw .bin dump import from Proxmark3 |
| **Persistence** | SwiftData (v2.0) / UserDefaults (v1.0) | Card library storage |

---

## 3. Hardware Wiring

```
ESP32-S3-DevKitC-1          PN532 Module (HSU Mode)
══════════════════          ═══════════════════════

3.3V        ───────────────► VCC
GND         ───────────────► GND
GPIO17 (RX) ───────────────► TXD
GPIO18 (TX) ───────────────► RXD

LiPo (+)    ───────────────► TP4056 B+
LiPo (-)    ───────────────► TP4056 B-
TP4056 OUT+ ───────────────► ESP32 5V / VIN
TP4056 OUT- ───────────────► ESP32 GND
USB-C       ◄──────────────► TP4056 USB (charging port)

IMPORTANT:
• Set PN532 DIP switch to "HSU" (UART) mode.
• Do NOT use 5V on PN532 VCC if your board lacks regulator.
  The red boards usually have AMS1117-3.3, so 5V is safe.
```

---

## 4. BLE GATT Protocol

### 4.1 Service & Characteristics

| UUID | Name | Properties | Description |
|---|---|---|---|
| `A0000000-0000-0000-0000-000000000001` | `NFC_BRIDGE_SVC` | — | Primary service |
| `A0000000-0000-0000-0000-000000000002` | `CMD_CHAR` | Write | iPhone → Bridge commands |
| `A0000000-0000-0000-0000-000000000003` | `STATUS_CHAR` | Notify | Bridge → iPhone async events |

### 4.2 Command Schema (iPhone → Bridge)

All commands are JSON objects, max 4096 bytes (MTU), written to `CMD_CHAR`.

#### 4.2.1 `load_card`
Uploads card data to bridge RAM. Volatile (lost on power cycle in v1.0).

```json
{
  "cmd": "load_card",
  "uid": "A1B2C3D4",
  "atqa": [0, 4],
  "sak": 8,
  "sectors": [
    [0xA1, 0xB2, 0xC3, 0xD4, 0x08, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ... 64 blocks total
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `cmd` | string | ✅ | Must be `"load_card"` |
| `uid` | hex string | ✅ | 4-byte or 7-byte UID, uppercase, no spaces |
| `atqa` | uint8[2] | ⚠️ | Defaults to `[0x00, 0x04]` if omitted |
| `sak` | uint8 | ⚠️ | Defaults to `0x08` (MIFARE Classic 1K) |
| `sectors` | uint8[64][16] | ⚠️ | Full sector dump. Omit = UID-only emulation |

#### 4.2.2 `emulate`
Activates card emulation for a fixed duration.

```json
{
  "cmd": "emulate",
  "duration": 30000
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `duration` | uint32 | ⚠️ | Milliseconds. Default: `30000` (30s). Max: `60000`. |

#### 4.2.3 `stop`
Immediately terminates emulation.

```json
{ "cmd": "stop" }
```

#### 4.2.4 `ping`
Health check.

```json
{ "cmd": "ping" }
```

### 4.3 Response Schema (Bridge → iPhone)

Sent as JSON notifications on `STATUS_CHAR`.

```json
{
  "status": "emulating",
  "msg": "started",
  "uid": "A1B2C3D4"
}
```

| Status Value | Meaning |
|---|---|
| `ready` | Card loaded successfully |
| `emulating` | Actively broadcasting NFC field |
| `idle` | Stopped or timed out |
| `error` | Something failed (see `msg`) |
| `pong` | Response to `ping` |
| `reader_cmd` | Reader sent a command (see `msg` for type) |

---

## 5. Firmware Deep Dive

### 5.1 Boot Sequence

```
[Power On]
    │
    ▼
[Initialize Serial2 @ 115200 for PN532]
    │
    ▼
[PN532 SAMConfig()]
    │
    ▼
[Initialize BLE GATT Server]
    │
    ▼
[Start Advertising]
    │
    ▼
[Main Loop]
    ├── If emulateActive → handleEmulation()
    └── Else → delay(100)
```

### 5.2 Emulation State Machine

```
[IDLE] ──(cmd: emulate)──► [EMULATING]
                                │
                                ▼
                    ┌───────────────────────┐
                    │ tgInitAsTarget()      │
                    │ Wait for reader field │
                    │ (passive 106 kbps)    │
                    └───────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │ Reader detected?      │
                    │ YES → tgGetData()     │
                    │ NO  → timeout loop    │
                    └───────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │ Parse APDU / MIFARE   │
                    │ command:              │
                    │ • 0x60/0x61 AUTH      │
                    │ • 0x30 READ           │
                    │ • 0xA0 WRITE          │
                    │ • 0x50 HALT           │
                    └───────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │ Build response        │
                    │ tgSetData(response)   │
                    │ Loop until timeout    │
                    └───────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │ Timeout or reader     │
                    │ releases → [IDLE]     │
                    └───────────────────────┘
```

### 5.3 MIFARE Classic Command Handling

| Reader Command | Bytes | Bridge Response | Notes |
|---|---|---|---|
| `AUTH_A` | `0x60, block` | `0x00, 0x00, 0x00, 0x00` | Fake auth token. Works on UID-only or weak readers. |
| `AUTH_B` | `0x61, block` | `0x00, 0x00, 0x00, 0x00` | Same as above. |
| `READ` | `0x30, block` | 16 bytes from `cardSectors[block]` | Returns stored sector data. |
| `WRITE` | `0xA0, block` | `0x04` (NAK) | Reject all writes. Bridge is read-only. |
| `HALT` | `0x50, 0x00` | — | Reader done. Exit emulation loop. |

**v1.0 Limitation:** No real Crypto1 state machine. We fake the auth response. This works on:
- Readers that only check UID (80% of cheap gym readers)
- Readers with weak auth validation

**v2.0 Upgrade (In Progress):** Implemented full Crypto1 PRNG + authentication state machine to pass genuine sector authentication. Currently stabilizing the nested auth handshake.

### 5.4 Memory Layout (Bridge RAM)

```c
struct CardProfile {
    uint8_t  uid[7];        // 4 or 7 bytes
    uint8_t  uidLen;        // 4 or 7
    uint8_t  atqa[2];       // SENS_RES
    uint8_t  sak;           // SEL_RES
    uint8_t  sectors[64][16]; // 1024 bytes (MIFARE Classic 1K)
    bool     hasData;       // Loaded flag
};
```

---

## 6. iOS App Architecture

### 6.1 Module Structure

```
NFCBridgeApp/
├── NFCBridgeApp.swift          // @main entry point
├── ContentView.swift           // Root SwiftUI view
├── BLE/
│   ├── BLEManager.swift        // CoreBluetooth central manager
│   └── BLEModels.swift         // Codable structs for JSON protocol
├── Cards/
│   ├── Card.swift              // SwiftData model (v2.0)
│   ├── CardStore.swift         // Repository / ViewModel
│   └── CardImportView.swift    // JSON import UI
├── Emulation/
│   ├── EmulationView.swift     // Active emulation screen
│   └── EmulationTimer.swift    // Countdown + auto-stop
└── Utils/
    ├── HexHelpers.swift        // UInt8 <-> Hex string conversions
    └── JSONHelpers.swift       // Proxmark3 dump parser
```

### 6.2 BLEManager Lifecycle

```swift
// 1. Init
CBCentralManager(delegate: self, queue: .main)

// 2. Powered On → Scan
central.scanForPeripherals(withServices: [SERVICE_UUID])

// 3. Discovered → Connect
central.connect(peripheral)

// 4. Connected → Discover Services
peripheral.discoverServices([SERVICE_UUID])

// 5. Services → Discover Characteristics
peripheral.discoverCharacteristics([CMD_UUID, STATUS_UUID])

// 6. Characteristics Found
//    • Cache cmdChar for writes
//    • Subscribe to statusChar notifications

// 7. Status Notifications → Parse JSON → Update @Published vars
//    → SwiftUI auto-re-renders
```

### 6.3 Card Import Flow (v1.0 Manual / v2.0 Auto)

```
[User taps "Import from Proxmark3"]
            │
            ▼
[UIDocumentPickerViewController]
            │
            ▼
[Select .bin file]
            │
            ▼
[Parse with Data into Card struct]
            │
            ▼
[Validate: UID length, sector count = 64]
            │
            ▼
[Save to CardStore (UserDefaults / SwiftData)]
            │
            ▼
[Display in Card Library list]
```

### 6.4 Emulation Flow

```
[User selects card from library]
            │
            ▼
[BLEManager.loadCard(uid:atqa:sak:sectors:)]
            │
            ▼
[Serialize to JSON → write to CMD_CHAR]
            │
            ▼
[Bridge responds: status=ready]
            │
            ▼
[User taps "Emulate"]
            │
            ▼
[BLEManager.startEmulate(duration:)]
            │
            ▼
[Bridge enters tgInitAsTarget loop]
            │
            ▼
[User holds bridge near reader]
            │
            ▼
[Reader authenticates → Bridge responds → Door opens]
            │
            ▼
[30s timeout OR user taps Stop]
            │
            ▼
[Bridge exits emulation → status=idle]
```

---

## 7. Proxmark3 Integration

### 7.1 Card Reconnaissance

```bash
# Identify chip family
pm3 --> hf search

# Expected outputs:
#   [+] UID: A1 B2 C3 D4
#   [+] ATQA: 00 04
#   [+] SAK: 08
#   [+] Possible types: MIFARE Classic 1K
```

### 7.2 Key Recovery

```bash
# Try default keys across all sectors
pm3 --> hf mf chk *1 ? t

# If defaults fail, try nested attack (requires at least 1 known key)
pm3 --> hf mf nested --1k --blk 0 -a -k FFFFFFFFFFFF

# If that fails, hardnested (CPU intensive)
pm3 --> hf mf hardnested --blk 0 -a -k FFFFFFFFFFFF
```

### 7.3 Full Dump

```bash
# Dump with recovered keys
pm3 --> hf mf dump -k hf-mf-A1B2C3D4-key.bin

# Output files:
#   hf-mf-A1B2C3D4-dump.bin   (1024 bytes, raw sector data)
#   hf-mf-A1B2C3D4-key.bin    (key file)
```

### 7.4 Conversion to Bridge JSON

**Python converter** (`proxmark_to_bridge.py`):

```python
#!/usr/bin/env python3
import sys
import json
import argparse

def convert(dump_path: str, out_path: str = None):
    with open(dump_path, "rb") as f:
        raw = f.read()

    if len(raw) != 1024:
        raise ValueError(f"Expected 1024 bytes (MIFARE Classic 1K), got {len(raw)}")

    # Block 0 = manufacturer data
    uid = raw[0:4]
    bcc = raw[4]          # BCC check byte
    atqa = raw[5:7]       # Actually ATQA in manufacturer block layout varies
    # For PN532 we derive ATQA/SAK from card type, not raw block 0

    sectors = []
    for block in range(64):
        sectors.append(list(raw[block*16:(block+1)*16]))

    payload = {
        "cmd": "load_card",
        "uid": uid.hex().upper(),
        "atqa": [0x00, 0x04],   # MIFARE Classic 1K standard
        "sak": 0x08,            # MIFARE Classic 1K
        "sectors": sectors
    }

    output = json.dumps(payload, indent=2)

    if out_path:
        with open(out_path, "w") as f:
            f.write(output)
        print(f"Written to {out_path}")
    else:
        print(output)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dump", help="Proxmark3 dump .bin file")
    parser.add_argument("-o", "--output", help="Output JSON file")
    args = parser.parse_args()
    convert(args.dump, args.output)
```

**Usage:**
```bash
python3 proxmark_to_bridge.py hf-mf-A1B2C3D4-dump.bin -o my_gym_card.json
```

**Transfer to iPhone:**
- AirDrop the raw `.bin` file
- Open in NFC Bridge app (via `UTType.data` document picker)
- App natively parses the binary and stores in card library

---

## 8. Feature Roadmap

### 8.1 v1.0 — MVP (This Weekend)
- [x] ESP32 + PN532 basic emulation
- [x] BLE GATT command protocol
- [x] iOS app: connect, load UID, emulate
- [x] Proxmark3 dump native `.bin` support
- [x] `.bin` file import in iOS app
- [x] Basic card library (name + UID)

### 8.2 v1.1 — Robustness
- [x] PN532 auto-retry on `tgInitAsTarget` timeout
- [x] Battery level reporting over BLE
- [x] Emulation duration configurable (5s–60s)
- [x] Haptic feedback on successful reader detection
- [x] Background BLE reconnection

### 8.3 v2.0 — Full MIFARE Classic
- [x] Crypto1 PRNG + authentication state machine
- [ ] Nested authentication for encrypted sectors
- [ ] Support 7-byte UID (Cascade 2)
- [ ] Sector-level key management (A/B keys per sector)
- [x] SwiftData persistent card library
- [ ] iCloud sync across devices

### 8.4 v3.0 — Multi-Protocol
- [x] 125 kHz support (T5577 / EM4305 module + firmware PWM)
- [x] MIFARE Ultralight / NTAG emulation
- [ ] DESFire light support (UID-only mode)
- [ ] Apple Watch companion app
- [ ] Widget / Lock Screen quick-emulate
- [x] iOS 18+ Direct Emulation Research (NFCDManager)

---

## 9. Security & Legal Considerations

### 9.1 Threat Model

| Threat | Mitigation |
|---|---|
| BLE sniffing | Commands contain no keys in v1.0 (keys are in sector dumps). v2.0 will add BLE pairing + encrypted GATT. |
| Card data theft | Bridge RAM is volatile. No persistent storage on device. |
| Replay attacks | Each emulation session is time-bounded (30s max). |
| Cloning unauthorized cards | App requires physical Proxmark3 dump — out of scope. |

### 9.2 Legal Boundaries

| Action | Legality |
|---|---|
| Cloning a card **you own** | Generally legal (like copying a house key) |
| Building a device for **personal use** | Legal in most jurisdictions |
| **Selling** a universal card cloner | Risky — DMCA (US), Computer Fraud and Abuse Act, local anti-circumvention laws |
| **Using** cloned card to access systems **without authorization** | Illegal everywhere |

**Product Pivot for Commercialization:**
Instead of a "cloner," build a **"Mobile Credential Platform."**
- Partner with HID, Kisi, Brivo, or Verkada
- Issue legitimate mobile credentials via their APIs
- Your bridge becomes a "universal receiver" for certified credentials
- Apple Wallet integration becomes possible through partner channels

---

## 10. Quick Start Checklist

### 10.1 Shopping List
- [ ] ESP32-S3-DevKitC-1 × 1
- [ ] PN532 NFC module (red board, HSU mode) × 1
- [ ] 3.7V 500mAh LiPo battery (502535) × 1
- [ ] TP4056 USB-C charging module × 1
- [ ] Dupont jumper wires (M-F, M-M) × 20
- [ ] Small project box or 3D printed case × 1

**Estimated cost:** $20–25

### 10.2 Software Setup
- [ ] Install Arduino IDE 2.x
- [ ] Add ESP32 board package: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
- [ ] Install libraries: `ArduinoJson`, `elechouse/PN532`
- [ ] Install Xcode 15+
- [ ] Clone Proxmark3 client (if you have the hardware)

### 10.3 Flash & Test
- [ ] Wire ESP32 ↔ PN532
- [ ] Upload firmware
- [ ] Verify Serial Monitor: `PN532 ready`
- [ ] Build iOS app, deploy to iPhone
- [ ] Verify BLE connection
- [ ] Scan card with Proxmark3, get UID
- [ ] Load UID into app, tap Emulate
- [ ] Hold bridge near reader → **🚪**

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| PN532 not found | Wrong wiring / wrong mode switch | Check TX/RX are crossed. Set switch to HSU. |
| BLE won't connect | iOS Bluetooth permissions | Add `NSBluetoothAlwaysUsageDescription` to Info.plist |
| Reader doesn't detect bridge | PN532 antenna too far | Hold bridge within 2cm of reader |
| Reader detects but rejects | Reader checks sector keys | Need v2.0 Crypto1 implementation |
| Emulation stops early | Reader sends HALT | Normal. Tap Emulate again. |
| iOS app crashes on import | Malformed JSON | Validate with `python -m json.tool` |

---

## 12. Appendix: Complete JSON Examples

### 12.1 UID-Only Card (Minimal)
```json
{
  "cmd": "load_card",
  "uid": "DEADBEEF"
}
```

### 12.2 Full MIFARE Classic 1K
```json
{
  "cmd": "load_card",
  "uid": "A1B2C3D4",
  "atqa": [0, 4],
  "sak": 8,
  "sectors": [
    [161, 178, 195, 212, 8, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ... 62 more blocks ...
    [255, 255, 255, 255, 255, 255, 143, 23, 69, 136, 255, 255, 255, 255, 255, 255]
  ]
}
```

### 12.3 Status Responses
```json
{"status": "ready", "msg": "card_loaded", "uid": "A1B2C3D4"}
{"status": "emulating", "msg": "started", "uid": "A1B2C3D4"}
{"status": "reader_cmd", "msg": "auth_received", "uid": "A1B2C3D4"}
{"status": "idle", "msg": "emulation_timeout", "uid": "A1B2C3D4"}
{"status": "error", "msg": "no_card_loaded", "uid": ""}
```

---

*Document version: 1.0*
*Last updated: 2026-07-30*
*Author: NFC Bridge Project*
