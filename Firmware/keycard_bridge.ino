#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>
#include <BLE2902.h>
#include <mbedtls/gcm.h>
#include "DESFireEmulator.h"

// Initialize DESFire Emulator
DESFireEmulator desfireEmulator;

#include <Wire.h>
#include <SPI.h>
#include <PN532_HSU.h>
#include <PN532.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Update.h>
#include "mbedtls/gcm.h"

#include "crapto1.h"

// 32-byte PSK for AES-256-GCM
const unsigned char psk[32] = {
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
    0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20
};

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
  Serial.println("Starting OTA AP: KeyCard-OTA");
  WiFi.softAP("KeyCard-OTA", "keycard_update");
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);

  server.on("/", HTTP_GET, []() {
    server.send(200, "text/plain", "KeyCard OTA Update Server Ready");
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

void sendEncryptedNotification(String jsonStr) {
    if (deviceConnected && pTxCharacteristic != NULL) {
        size_t pt_len = jsonStr.length();
        unsigned char nonce[12] = {0}; // Static for prototype
        unsigned char tag[16];
        unsigned char* ciphertext = (unsigned char*)malloc(pt_len);
        
        mbedtls_gcm_context ctx;
        mbedtls_gcm_init(&ctx);
        mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, psk, 256);
        mbedtls_gcm_crypt_and_tag(&ctx, MBEDTLS_GCM_ENCRYPT, pt_len, nonce, 12, NULL, 0, (const unsigned char*)jsonStr.c_str(), ciphertext, 16, tag);
        mbedtls_gcm_free(&ctx);
        
        size_t combined_len = 12 + pt_len + 16;
        unsigned char* combined = (unsigned char*)malloc(combined_len);
        memcpy(combined, nonce, 12);
        memcpy(combined + 12, ciphertext, pt_len);
        memcpy(combined + 12 + pt_len, tag, 16);
        
        pTxCharacteristic->setValue(combined, combined_len);
        pTxCharacteristic->notify();
        
        free(ciphertext);
        free(combined);
    }
}

void sendAuthNotification() {
    DynamicJsonDocument doc(256);
    doc["status"] = "reader_cmd";
    doc["msg"] = "auth_received";
    String out;
    serializeJson(doc, out);
    sendEncryptedNotification(out);
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
      std::string rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 28) { // 12 nonce + 16 tag + at least 1 byte ciphertext
        size_t ciphertext_len = rxValue.length() - 28;
        unsigned char nonce[12];
        unsigned char tag[16];
        unsigned char* ciphertext = (unsigned char*)malloc(ciphertext_len);
        unsigned char* plaintext = (unsigned char*)malloc(ciphertext_len + 1);

        memcpy(nonce, rxValue.data(), 12);
        memcpy(ciphertext, rxValue.data() + 12, ciphertext_len);
        memcpy(tag, rxValue.data() + 12 + ciphertext_len, 16);

        mbedtls_gcm_context ctx;
        mbedtls_gcm_init(&ctx);
        mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, psk, 256);

        int ret = mbedtls_gcm_auth_decrypt(&ctx, ciphertext_len, nonce, 12, NULL, 0, tag, 16, ciphertext, plaintext);
        mbedtls_gcm_free(&ctx);

        if (ret == 0) {
          plaintext[ciphertext_len] = '\0';
          String jsonStr = String((char*)plaintext);
          
          DynamicJsonDocument doc(16384);
          DeserializationError error = deserializeJson(doc, jsonStr);
          
          if (!error) {
          const char* cmd = doc["cmd"];
          if (String(cmd) == "load_card") {
            const char* type = doc["type"];
            if (type) {
                String typeStr = String(type);
                currentType = typeStr;
                
                if (currentType == "desfire") {
                    if (doc.containsKey("desfireData")) {
                        String emlData = doc["desfireData"].as<String>();
                        desfireEmulator.loadEML(emlData);
                    }
                }
                
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
        } else {
            Serial.println("Decryption Error");
        }
        free(ciphertext);
        free(plaintext);
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
  BLEDevice::init("KeyCard Bridge");

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

void playFSKBit(bool bit) {
    if (bit == 0) {
        // Logic 0: 12.5 kHz (5 cycles of 80us period)
        for (int i = 0; i < 5; i++) {
            ledcWrite(0, 128); // Carrier ON
            delayMicroseconds(40);
            ledcWrite(0, 0);   // Carrier OFF
            delayMicroseconds(40);
        }
    } else {
        // Logic 1: 15.625 kHz (6 cycles of 64us period)
        for (int i = 0; i < 6; i++) {
            ledcWrite(0, 128); // Carrier ON
            delayMicroseconds(32);
            ledcWrite(0, 0);   // Carrier OFF
            delayMicroseconds(32);
        }
    }
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
        sendEncryptedNotification(out);
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
                        if (currentType == "desfire") {
                            uint8_t txBuffer[64];
                            int txLen = desfireEmulator.processAPDU(rxBuffer, rxLen, txBuffer);
                            if (txLen > 0) {
                                nfc.tgSetData(txBuffer, txLen);
                            }
                        } else if (currentType == "desfireLight") {
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
                            } else if (cmd == 0x60) { // GET_VERSION (NTAG215 specific)
                                // NTAG215 Version Information: NXP, NTAG, 50pF, 1.0, 504 bytes, ISO14443-3
                                uint8_t version[8] = { 0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03 };
                                nfc.tgSetData(version, 8);
                            } else if (cmd == 0x3A) { // FAST_READ
                                uint8_t startPage = rxBuffer[1];
                                uint8_t endPage = rxBuffer[2];
                                if (startPage <= endPage && endPage < 135) {
                                    int numPages = endPage - startPage + 1;
                                    int byteCount = numPages * 4;
                                    if (byteCount <= 64) { // Typical PN532 buffer limit for tgSetData
                                        uint8_t resp[64];
                                        for (int i = 0; i < numPages; i++) {
                                            int p = startPage + i;
                                            resp[i*4] = currentUlData[p][0];
                                            resp[i*4+1] = currentUlData[p][1];
                                            resp[i*4+2] = currentUlData[p][2];
                                            resp[i*4+3] = currentUlData[p][3];
                                        }
                                        nfc.tgSetData(resp, byteCount);
                                    }
                                }
                            } else if (cmd == 0x1B) { // PWD_AUTH
                                // NTAG215 Password Authentication. 
                                // Return the 2-byte PACK from Page 134 to fake a successful authentication.
                                uint8_t pack[2] = { currentUlData[134][0], currentUlData[134][1] };
                                nfc.tgSetData(pack, 2);
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
                                    uint32_t ar_enc = rxBuffer[4] | (rxBuffer[5] << 8) | (rxBuffer[6] << 16) | (rxBuffer[7] << 24);
                                    
                                    // Feed the encrypted reader nonce into the cipher
                                    crypto1_word(&crypto1, nr_enc, 1);
                                    
                                    // Advance cipher state by decrypting the reader answer (aR)
                                    crypto1_word(&crypto1, ar_enc, 0);
                                    
                                    isAuthenticated = true;
                                    
                                    // Calculate Tag Answer (aT) - PRNG successor of nT shifted 64 times
                                    uint32_t at_plain = prng_successor(nt_val, 64); 
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
        // 1. Preamble (11 zeroes, 34 ones)
        for (int i=0; i<11; i++) playFSKBit(0);
        for (int i=0; i<34; i++) playFSKBit(1);
        
        // 2. Wiegand Payload
        // Parse hex string to 64-bit integer
        uint64_t payload = strtoull(currentUidString.c_str(), NULL, 16);
        
        // 3. Stream bits (assuming standard 26-bit HID Prox)
        for (int i = 25; i >= 0; i--) {
            bool b = (payload >> i) & 1;
            playFSKBit(b);
        }
    }
    
    delay(10);
}
