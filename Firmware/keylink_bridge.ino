#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>
#include <BLE2902.h>
#include <Wire.h>
#include <SPI.h>
#include <PN532_HSU.h>
#include <PN532.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Update.h>

#include "crapto1.h"

// Hardware Pins
#define BATTERY_PIN 9

// BLE UUIDs
#define SERVICE_UUID           "0000180F-0000-1000-8000-00805F9B34FB" // Example Battery service, we should probably use a custom one
#define CHARACTERISTIC_UUID_RX "00002A19-0000-1000-8000-00805F9B34FB"
#define CHARACTERISTIC_UUID_TX "00002A19-0000-1000-8000-00805F9B34FB"

BLEServer *pServer = NULL;
BLECharacteristic * pTxCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// PN532 setup for HSU (Hardware Serial)
HardwareSerial PN532Serial(1); // Use UART1
PN532_HSU pn532hsu(PN532Serial);
PN532 nfc(pn532hsu);

bool isEmulating = false;
bool isEmulating125 = false;
uint8_t currentUid[4] = {0x01, 0x02, 0x03, 0x04};
String currentUidString = "";
uint8_t currentAtqa[2] = {0x04, 0x00};
uint8_t currentSak = 0x08;

// MIFARE Classic 1K holds 64 blocks of 16 bytes
uint8_t currentCardData[64][16]; 
// MIFARE Ultralight holds up to 135 pages of 4 bytes (NTAG215)
uint8_t currentUlData[135][4];

bool cardDataLoaded = false;
String currentType = "";

// Crypto1 State
struct crypto1_state crypto1;
bool isAuthenticated = false;

// Battery Tracker
unsigned long lastBatteryCheck = 0;

// OTA Setup
bool isOTA = false;
WebServer server(80);

void startOTA() {
  Serial.println("Starting OTA AP: KeyLink-OTA");
  WiFi.softAP("KeyLink-OTA", "keylink_update");
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);

  server.on("/", HTTP_GET, []() {
    server.send(200, "text/plain", "KeyLink OTA Update Server Ready");
  });

  server.on("/update", HTTP_POST, []() {
    server.sendHeader("Connection", "close");
    server.send(200, "text/plain", (Update.hasError()) ? "FAIL" : "OK");
    ESP.restart();
  }, []() {
    HTTPUpload& upload = server.upload();
    if (upload.status == UPLOAD_FILE_START) {
      Serial.printf("Update: %s\n", upload.filename.c_str());
      if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
        Update.printError(Serial);
      }
    } else if (upload.status == UPLOAD_FILE_WRITE) {
      if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
        Update.printError(Serial);
      }
    } else if (upload.status == UPLOAD_FILE_END) {
      if (Update.end(true)) {
        Serial.printf("Update Success: %u\nRebooting...\n", upload.totalSize);
      } else {
        Update.printError(Serial);
      }
    }
  });

  server.begin();
  Serial.println("HTTP server started");
}

void sendAuthNotification() {
    if (deviceConnected && pTxCharacteristic != NULL) {
        DynamicJsonDocument doc(256);
        doc["status"] = "reader_cmd";
        doc["msg"] = "auth_received";
        String out;
        serializeJson(doc, out);
        pTxCharacteristic->setValue(out.c_str());
        pTxCharacteristic->notify();
    }
}

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue().c_str();
      if (rxValue.length() > 0) {
        // Serial.println("Received Payload:"); // Disable print for large payloads
        
        DynamicJsonDocument doc(16384);
        DeserializationError error = deserializeJson(doc, rxValue);
        
        if (!error) {
          const char* cmd = doc["cmd"];
          if (String(cmd) == "load_card") {
            const char* type = doc["type"];
            if (type) {
                currentType = String(type);
                if (currentType == "hidProx26") {
                    currentUidString = doc["uid"].as<String>();
                    Serial.println("HID Prox loaded.");
                } else if (currentType == "mifareUltralight") {
                    JsonArray pages = doc["pages"];
                    if (!pages.isNull()) {
                        int numPages = pages.size();
                        if (numPages <= 135) {
                            for (int i = 0; i < numPages; i++) {
                                JsonArray page = pages[i];
                                for (int j = 0; j < 4; j++) {
                                    currentUlData[i][j] = page[j].as<uint8_t>();
                                }
                            }
                            cardDataLoaded = true;
                            Serial.println("Ultralight Pages loaded into memory.");
                        }
                    }
                } else if (currentType == "desfireLight") {
                    // DESFire Light (UID only)
                    currentUidString = doc["uid"].as<String>();
                    // Convert hex string to byte array
                    int len = currentUidString.length();
                    for(int i = 0; i < len / 2 && i < 7; i++) {
                        String byteString = currentUidString.substring(i*2, i*2+2);
                        currentUid[i] = (uint8_t) strtol(byteString.c_str(), NULL, 16);
                    }
                    Serial.println("DESFire Light (UID-only) loaded.");
                } else {
                    // Parse sectors for MIFARE Classic
                    JsonArray sectors = doc["sectors"];
                    if (!sectors.isNull() && sectors.size() == 64) {
                        for (int i = 0; i < 64; i++) {
                            JsonArray block = sectors[i];
                            for (int j = 0; j < 16; j++) {
                                currentCardData[i][j] = block[j].as<uint8_t>();
                            }
                        }
                        cardDataLoaded = true;
                        Serial.println("64 Sectors loaded into memory.");
                    }
                }
            }
            Serial.println("Card loaded into memory.");
          } else if (String(cmd) == "emulate") {
            int duration = 30000;
            if (doc.containsKey("duration")) {
                duration = doc["duration"];
            }
            isEmulating = true;
            isEmulating125 = false;
            isAuthenticated = false;
            Serial.printf("Started 13.56MHz emulation (Duration: %d ms)\n", duration);
          } else if (String(cmd) == "emulate_125") {
            isEmulating125 = true;
            isEmulating = false;
            
            // Setup 125kHz carrier on GPIO 4 using LEDC channel 0
            ledcSetup(0, 125000, 8); // Channel 0, 125 kHz, 8-bit resolution
            ledcAttachPin(4, 0);
            ledcWrite(0, 128); // 50% duty cycle
            
            Serial.println("Started 125kHz emulation on GPIO 4");
          } else if (String(cmd) == "stop") {
            isEmulating = false;
            isEmulating125 = false;
            ledcDetachPin(4); // Stop 125kHz carrier
            Serial.println("Stopped emulation");
          } else if (String(cmd) == "enter_ota") {
            isOTA = true;
            isEmulating = false;
            isEmulating125 = false;
            Serial.println("Entering OTA Mode");
            startOTA();
          }
        } else {
            Serial.println("JSON Parse Error");
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  PN532Serial.begin(115200, SERIAL_8N1, 18, 17); // RX=18, TX=17 for ESP32
  nfc.begin();
  
  pinMode(BATTERY_PIN, INPUT);

  uint32_t versiondata = nfc.getFirmwareVersion();
  if (! versiondata) {
    Serial.print("Didn't find PN53x board");
    while (1); // halt
  }

  // Create the BLE Device
  BLEDevice::init("KeyLink Bridge");

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create a BLE Characteristic
  pTxCharacteristic = pService->createCharacteristic(
										CHARACTERISTIC_UUID_TX,
										BLECharacteristic::PROPERTY_NOTIFY
									);
                      
  pTxCharacteristic->addDescriptor(new BLE2902());
  pTxCharacteristic->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED | ESP_GATT_PERM_WRITE_ENCRYPTED);

  BLECharacteristic * pRxCharacteristic = pService->createCharacteristic(
											 CHARACTERISTIC_UUID_RX,
											BLECharacteristic::PROPERTY_WRITE
										);

  pRxCharacteristic->setCallbacks(new MyCallbacks());
  pRxCharacteristic->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED | ESP_GATT_PERM_WRITE_ENCRYPTED);

  // Start the service
  pService->start();

  // Setup BLE Security
  BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND);
  pSecurity->setCapability(ESP_IO_CAP_OUT);
  pSecurity->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  
  uint32_t passkey = 123456;
  esp_ble_gap_set_security_param(ESP_BLE_SM_SET_STATIC_PASSKEY, &passkey, sizeof(uint32_t));

  // Start advertising
  pServer->getAdvertising()->start();
  Serial.println("Waiting for a client connection to notify...");
}

void loop() {
    if (isOTA) {
        server.handleClient();
        delay(2);
        return;
    }
    
    // disconnecting
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // give the bluetooth stack the chance to get things ready
        pServer->startAdvertising(); // restart advertising
        Serial.println("Start advertising");
        oldDeviceConnected = deviceConnected;
    }
    // connecting
    if (deviceConnected && !oldDeviceConnected) {
        // do stuff here on connecting
        oldDeviceConnected = deviceConnected;
    }
    
    // Battery Notification Loop (every 5 seconds)
    if (deviceConnected && (millis() - lastBatteryCheck > 5000)) {
        lastBatteryCheck = millis();
        int adc = analogRead(BATTERY_PIN);
        // Assuming 1/2 voltage divider: 4.2V -> 2.1V (~2600), 3.2V -> 1.6V (~1980)
        int percentage = map(adc, 1980, 2600, 0, 100);
        if (percentage < 0) percentage = 0;
        if (percentage > 100) percentage = 100;
        
        DynamicJsonDocument doc(256);
        doc["battery"] = percentage;
        String out;
        serializeJson(doc, out);
        pTxCharacteristic->setValue(out.c_str());
        pTxCharacteristic->notify();
    }
    
    if (isEmulating && cardDataLoaded) {
        // Initialize as MIFARE target
        uint8_t command[] = {
            0x8C, // tgInitAsTarget
            0x00, // Mode: passive only
            0x04, 0x00, // SENS_RES
            0x12, 0x34, 0x56, // NFCID1t
            0x20, // SEL_RES
            0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // Felica
            0,0,0,0,0,0,0,0,0,0, // NFCID3t
            0, 0 // length
        };
        
        if (currentType == "mifareUltralight") {
            command[2] = 0x44; // ATQA
            command[3] = 0x00;
            command[7] = 0x00; // SAK
            
            // Set first 3 bytes of UID
            command[4] = currentUlData[0][0];
            command[5] = currentUlData[0][1];
            command[6] = currentUlData[0][2];
        } else if (currentType == "desfireLight") {
            command[2] = 0x44; // ATQA
            command[3] = 0x03;
            command[7] = 0x20; // SAK (ISO/IEC 14443-4)
            
            // Set first 3 bytes of UID
            command[4] = currentUid[0];
            command[5] = currentUid[1];
            command[6] = currentUid[2];
        } else {
            // Copy real UID if available
            command[4] = currentCardData[0][0];
            command[5] = currentCardData[0][1];
            command[6] = currentCardData[0][2];
        }
        
        // This is a blocking call until a reader connects
        if (nfc.tgInitAsTarget(command, sizeof(command), 1000)) {
            Serial.println("Reader connected!");
            
            uint8_t rxBuffer[64];
            int rxLen = nfc.tgGetData(rxBuffer, sizeof(rxBuffer));
                    if (rxLen > 0) {
                        uint8_t cmd = rxBuffer[0];
                        if (currentType == "desfireLight") {
                            // UID-only mode: Ignore ISO-DEP APDU commands
                            Serial.println("Received APDU, ignoring (UID-only mode)");
                        } else if (currentType == "mifareUltralight") {
                            if (cmd == 0x30) { // READ
                                uint8_t page = rxBuffer[1];
                                uint8_t resp[16];
                                for (int i = 0; i < 4; i++) {
                                    int p = page + i;
                                    if (p < 135) {
                                        resp[i*4] = currentUlData[p][0];
                                        resp[i*4+1] = currentUlData[p][1];
                                        resp[i*4+2] = currentUlData[p][2];
                                        resp[i*4+3] = currentUlData[p][3];
                                    } else {
                                        resp[i*4] = 0; resp[i*4+1] = 0; resp[i*4+2] = 0; resp[i*4+3] = 0;
                                    }
                                }
                                nfc.tgSetData(resp, 16);
                            } else if (cmd == 0x50) { // HALT
                                // Do nothing
                            }
                        } else {
                            // Classic Logic
                            uint8_t decCmd = cmd;
                            uint8_t decBlock = rxBuffer[1];
                            
                            if (isAuthenticated) {
                                // Decrypt command and block (advances cipher state by 2 bytes)
                                decCmd = cmd ^ crypto1_byte(&crypto1, 0x00, 0);
                                decBlock = rxBuffer[1] ^ crypto1_byte(&crypto1, 0x00, 0);
                                // Skip the 2 CRC bytes sent by the reader to align cipher state for our response
                                if (rxLen >= 4) {
                                    crypto1_byte(&crypto1, 0x00, 0);
                                    crypto1_byte(&crypto1, 0x00, 0);
                                }
                            }
                            
                            if (decCmd == 0x60 || decCmd == 0x61) { // Auth A or Auth B (including Nested Auth)
                                if (isAuthenticated) {
                                    Serial.println("Nested Auth requested");
                                } else {
                                    Serial.println("Auth requested");
                                }
                                sendAuthNotification();
                                // 1. Extract block number
                                uint8_t block = decBlock;
                                uint8_t sector = block / 4;
                                
                                // 2. Get key from sector trailer (block 3 of the sector)
                                uint64_t key = 0;
                                if (decCmd == 0x60) {
                                    for(int i=0; i<6; i++) key = (key << 8) | currentCardData[sector * 4 + 3][i];
                                } else {
                                    for(int i=10; i<16; i++) key = (key << 8) | currentCardData[sector * 4 + 3][i];
                                }
                                
                                // 3. Generate random nonce (nT)
                                uint32_t nt_val = esp_random();
                                uint8_t nT[4] = { (uint8_t)(nt_val & 0xFF), (uint8_t)((nt_val >> 8) & 0xFF), (uint8_t)((nt_val >> 16) & 0xFF), (uint8_t)((nt_val >> 24) & 0xFF) };
                                
                                // For nested auth, nT is encrypted with the OLD session key before re-init
                                if (isAuthenticated) {
                                    for (int i=0; i<4; i++) {
                                        nT[i] ^= crypto1_byte(&crypto1, 0x00, 0);
                                    }
                                }
                                
                                // 4. Init Crypto1 (Reset state with new key)
                                crypto1_init(&crypto1, key);
                                
                                // Crypto1 initialization feed: UID XOR nT
                                uint32_t uid32 = currentCardData[0][0] | (currentCardData[0][1] << 8) | (currentCardData[0][2] << 16) | (currentCardData[0][3] << 24);
                                crypto1_word(&crypto1, uid32 ^ nt_val, 0);
                                
                                nfc.tgSetData(nT, 4);
                                
                                // 5. Receive reader's encrypted nonce (nR) and answer (aR)
                                rxLen = nfc.tgGetData(rxBuffer, sizeof(rxBuffer));
                                if (rxLen == 8) {
                                    // 6. Verify and send aT (encrypted answer)
                                    uint32_t nr_enc = rxBuffer[0] | (rxBuffer[1] << 8) | (rxBuffer[2] << 16) | (rxBuffer[3] << 24);
                                    
                                    // Feed the encrypted reader nonce into the cipher
                                    crypto1_word(&crypto1, nr_enc, 1);
                                    
                                    isAuthenticated = true;
                                    
                                    // Calculate Tag Answer (aT) - placeholder for PRNG successor
                                    uint32_t at_plain = 0xdeadbeef; 
                                    uint32_t at_enc = crypto1_word(&crypto1, at_plain, 0);
                                    
                                    uint8_t aT[4] = { (uint8_t)(at_enc & 0xFF), (uint8_t)((at_enc >> 8) & 0xFF), (uint8_t)((at_enc >> 16) & 0xFF), (uint8_t)((at_enc >> 24) & 0xFF) };
                                    nfc.tgSetData(aT, 4);
                                }
                            } else if (decCmd == 0x30 && isAuthenticated) { // Read
                                uint8_t block = decBlock;
                                uint8_t resp[16];
                                // Encrypt response using the advanced cipher state
                                for (int i=0; i<16; i++) {
                                    resp[i] = currentCardData[block][i] ^ crypto1_byte(&crypto1, 0x00, 0);
                                }
                                nfc.tgSetData(resp, 16);
                            } else if (decCmd == 0x50) { // Halt
                                isAuthenticated = false;
                            }
                        }
                    }
        }
    } else if (isEmulating125) {
        // Modulate the 125kHz carrier here
        // E.g., Amplitude Shift Keying (ASK) for HID Prox:
        // ledcWrite(0, 128); // Carrier ON
        // delayMicroseconds(XX);
        // ledcWrite(0, 0);   // Carrier OFF
        // delayMicroseconds(YY);
        // (Modulation logic goes here based on currentUidString)
    }
    
    delay(10);
}
