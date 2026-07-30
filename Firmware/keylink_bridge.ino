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
        Serial.println("Received Payload:");
        Serial.println(rxValue);
        
        StaticJsonDocument<1024> doc;
        DeserializationError error = deserializeJson(doc, rxValue);
        
        if (!error) {
          const char* cmd = doc["cmd"];
          if (String(cmd) == "load_card") {
            const char* uidHex = doc["uid"];
            // parse hex string to bytes
            // store in currentUid, currentAtqa, currentSak
            isEmulating = true;
            Serial.println("Card loaded and ready to emulate");
          } else if (String(cmd) == "stop") {
            isEmulating = false;
            Serial.println("Stopped emulation");
          }
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
    
    if (isEmulating) {
        // Set PN532 as target to emulate MIFARE Classic
        // tgInitAsTarget command sequence
        uint8_t command[] = {
            0x8C, // tgInitAsTarget
            0x00, // Mode: passive only
            
            // MIFARE Params
            0x04, 0x00, // SENS_RES (ATQA)
            0x12, 0x34, 0x56, // NFCID1t (UID) - not actually used, overridden by 0x33 later
            0x20, // SEL_RES (SAK)
            
            // FeliCa Params
            0x01, 0xFE, 0x05, 0x01, 0x86,
            0x04, 0x02, 0x02, 0x03, 0x00,
            0x4B, 0x02, 0x4F, 0x49, 0x8A,
            0x00, 0xFF, 0xFF,
            
            // NFCID3t
            0x01, 0xFE, 0x05, 0x01, 0x86, 0x04, 0x02, 0x02, 0x03, 0x00,
            
            // Length of general bytes
            0x00,
            // Length of historical bytes
            0x00
        };
        
        // nfc.tgInitAsTarget() wrap logic here
        // The elechouse library handles some of this, but we may need a custom command wrapper
    }
    
    delay(10);
}
