# KeyCard: Hardware Assembly & Testing Guide

This guide walks you through the final phase of the KeyCard project: physically building the proxy bridge and flashing the firmware we've written.

## 1. Bill of Materials (BOM)
To build the KeyCard bridge, you will need the following components:
1. **ESP32-S3 Development Board** (Any standard ESP32 or ESP32-S3 with exposed GPIOs will work).
2. **PN532 NFC RFID Module** (Typically the red "Elechouse V3" or similar blue clones).
3. **Jumper Wires** (Female-to-Female if both boards have header pins).
4. **Power Source** (A standard USB-C cable plugged into a power bank, or a 3.7V LiPo battery wired to the ESP32's `VIN`/`BAT` pins).
5. *(Optional but recommended)* A 3D printed case to keep the wiring secure in your pocket.

## 2. Configuring the PN532
The PN532 module supports three communication protocols: SPI, I2C, and HSU (High-Speed UART). The `keycard_bridge.ino` firmware is programmed to use **UART**.

Locate the two tiny DIP switches on the PN532 board and set them to **HSU Mode**:
- **Switch 1:** `OFF` (or `0`)
- **Switch 2:** `OFF` (or `0`)

> [!IMPORTANT]
> If these switches are set incorrectly, the ESP32 will fail to detect the PN532, and the firmware will halt.

## 3. Wiring Diagram
Disconnect the ESP32 from USB power before wiring. Connect the PN532 to the ESP32-S3 as follows:

| PN532 Pin | ESP32-S3 Pin | Description |
| :--- | :--- | :--- |
| **VCC** | **3.3V** or **5V** | Power (The PN532 operates natively on 3.3V but is generally 5V tolerant on VCC). |
| **GND** | **GND** | Ground connection. |
| **TXD** | **GPIO 18** (RX) | Transmit from PN532 goes to Receive on ESP32. |
| **RXD** | **GPIO 17** (TX) | Receive on PN532 goes to Transmit from ESP32. |

> [!TIP]
> If you are using a standard ESP32 (not S3) or different pins, you can modify the `RX_PIN` and `TX_PIN` definitions at the top of your `keycard_bridge.ino` file to match your physical wiring.

*(Note for 125kHz HID Prox testing: If you are building the v2.0 hardware with a 125kHz coil, ensure your coil circuit is connected to `GPIO 4` as defined in the firmware for the PWM carrier generation).*

## 4. Flashing the Firmware
Now that the hardware is assembled, it's time to upload the `keycard_bridge.ino` code:

1. Open **Arduino IDE**.
2. Connect the ESP32-S3 to your Mac via USB-C.
3. Select your board: **Tools > Board > ESP32S3 Dev Module** (or your specific board variant).
4. Select the port: **Tools > Port > /dev/cu.usbserial-...**
5. Install the required libraries via **Sketch > Include Library > Manage Libraries**:
   - `PN532` by Elechouse
   - `ArduinoJson` by Benoit Blanchon
6. Open the `keycard_bridge.ino` file.
7. Click **Upload**.

> [!NOTE]
> If the upload hangs at `Connecting...`, you may need to hold down the `BOOT` button on your ESP32 board until the upload starts.

## 5. Real-World Testing Protocol
Once the firmware is flashed, you are ready to test the end-to-end system:

1. **Power Up:** Plug the ESP32 into a portable power bank. Ensure the red power LED on the PN532 lights up.
2. **Connect App:** Open the KeyCard iOS app. It should automatically discover and connect to the "KeyCard Bridge" via Bluetooth.
3. **Select Card:** In the app's Card Library, tap the imported MIFARE card you wish to emulate.
4. **Emulate:** Tap the **"Emulate (Bridge)"** button. The app will send the JSON payload with the UID and Sector data to the ESP32.
5. **Unlock:** Hold the PN532 antenna up against the physical card reader. 
   - If the reader is "UID-only", it should instantly beep and unlock.
   - If the reader attempts a secure read, the ESP32 will use the embedded `crapto1` engine to authenticate and serve the requested block data.

> [!WARNING]
> Testing should only be performed on access control systems and locks that you own or have explicit authorization to audit.
