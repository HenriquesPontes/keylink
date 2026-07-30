#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include <SPI.h>
#include <PN532_HSU.h>
#include <PN532.h>
#include <ArduinoJson.h>

#include "crapto1.h"

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
uint8_t currentUid[4] = {0x01, 0x02, 0x03, 0x04};
uint8_t currentAtqa[2] = {0x04, 0x00};
uint8_t currentSak = 0x08;

// MIFARE Classic 1K holds 64 blocks of 16 bytes
uint8_t currentCardData[64][16]; 
bool cardDataLoaded = false;

// Crypto1 State
struct crypto1_state crypto1;
bool isAuthenticated = false;

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
            // Parse sectors
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
            
            isEmulating = true;
            isAuthenticated = false;
            Serial.println("Card loaded and ready to emulate");
          } else if (String(cmd) == "stop") {
            isEmulating = false;
            Serial.println("Stopped emulation");
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

  BLECharacteristic * pRxCharacteristic = pService->createCharacteristic(
											 CHARACTERISTIC_UUID_RX,
											BLECharacteristic::PROPERTY_WRITE
										);

  pRxCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();

  // Start advertising
  pServer->getAdvertising()->start();
  Serial.println("Waiting for a client connection to notify...");
}

void loop() {
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
    
    if (isEmulating && cardDataLoaded) {
        // Initialize as target
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
        
        // Copy real UID if available
        command[4] = currentCardData[0][0];
        command[5] = currentCardData[0][1];
        command[6] = currentCardData[0][2];
        
        // This is a blocking call until a reader connects
        if (nfc.tgInitAsTarget(command, sizeof(command), 1000)) {
            Serial.println("Reader connected!");
            
            uint8_t rxBuffer[64];
            int rxLen = nfc.tgGetData(rxBuffer, sizeof(rxBuffer));
            if (rxLen > 0) {
                uint8_t cmd = rxBuffer[0];
                if (cmd == 0x60 || cmd == 0x61) { // Auth A or Auth B
                    Serial.println("Auth requested");
                    // 1. Extract block number
                    uint8_t block = rxBuffer[1];
                    uint8_t sector = block / 4;
                    
                    // 2. Get key from sector trailer (block 3 of the sector)
                    // Key A is first 6 bytes, Key B is last 6 bytes
                    uint64_t key = 0;
                    if (cmd == 0x60) {
                        for(int i=0; i<6; i++) key = (key << 8) | currentCardData[sector * 4 + 3][i];
                    } else {
                        for(int i=10; i<16; i++) key = (key << 8) | currentCardData[sector * 4 + 3][i];
                    }
                    
                    // 3. Init Crypto1
                    crypto1_init(&crypto1, key);
                    
                    // 4. Generate random nonce (nT) and send
                    uint8_t nT[4] = {0x11, 0x22, 0x33, 0x44}; // In real app, use esp_random()
                    nfc.tgSetData(nT, 4);
                    
                    // 5. Receive reader's encrypted nonce (nR) and answer (aR)
                    rxLen = nfc.tgGetData(rxBuffer, sizeof(rxBuffer));
                    if (rxLen == 8) {
                        // 6. Verify and send aT (encrypted answer)
                        // (Crypto1 math omitted for brevity, stub assumes success)
                        isAuthenticated = true;
                        
                        uint8_t aT[4] = {0x00, 0x00, 0x00, 0x00}; // Encrypted answer
                        nfc.tgSetData(aT, 4);
                    }
                } else if (cmd == 0x30 && isAuthenticated) { // Read
                    uint8_t block = rxBuffer[1];
                    uint8_t resp[16];
                    // Decrypt read request, encrypt response
                    for (int i=0; i<16; i++) {
                        resp[i] = currentCardData[block][i]; 
                        // In real app, resp[i] ^= crypto1_byte(&crypto1, ...);
                    }
                    nfc.tgSetData(resp, 16);
                } else if (cmd == 0x50) { // Halt
                    isAuthenticated = false;
                }
            }
        }
    }
    
    delay(10);
}
