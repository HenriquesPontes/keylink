# KeyCard: Universal Mobile Key Platform

KeyCard is an open-source hardware and software stack that turns any iPhone into a universal access key by proxying NFC emulation through a BLE-connected wearable bridge. It bypasses Apple's strict NFC hardware locks without requiring a jailbreak or Apple Wallet hacks.

## 🏗️ Architecture

KeyCard consists of two main components:
1. **The iOS App (SwiftUI):** A clean, native interface to manage your card library. It imports raw `.bin` dumps directly (no python scripts required) and communicates with the hardware bridge over BLE.
2. **The Hardware Bridge (ESP32-S3 + PN532):** A small, battery-powered proxy device. It receives card data via BLE from the iPhone and emulates the physical NFC card (e.g., MIFARE Classic 1K) at the reader.

## 🚀 Core Features

- **Direct `.bin` Import:** Natively import 1024-byte `.bin` Proxmark3/MFOC dumps directly into the iOS app.
- **BLE Proxy Emulation:** The iPhone sends the card data to the ESP32 bridge over BLE, which then performs the actual 13.56MHz NFC emulation using a PN532 module.
- **Real Crypto1 Authentication (WIP):** Unlike simple UID cloners, the ESP32 firmware includes a real Crypto1 engine to dynamically extract keys from sector trailers and handle the MIFARE challenge/response handshake locally (to meet strict <5ms timing constraints).
- **UID-Only Fallback:** Can emulate just the UID for simpler, older gym readers.

## 🗺️ Road Map & Status

- [x] Basic ESP32 + PN532 emulation
- [x] BLE GATT command protocol
- [x] iOS app: Native `.bin` import and card library
- [x] Proxmark3 `.bin` dump integration (Full loop)
- [x] Initial Crypto1 engine integration in firmware
- [x] Stabilize Crypto1 handshake & nested authentication
- [ ] 125 kHz support (T5577)
- [x] Amiibo emulation (NTAG215 specific commands)


## ⚠️ Legal & Security

KeyCard is built for educational and personal use, allowing you to emulate cards **you already own**. It is not a tool for unauthorized access or commercial cloning. 

©️ 2026 Henriques Pontes, All rights reserved.