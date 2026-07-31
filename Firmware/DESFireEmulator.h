#ifndef DESFIRE_EMULATOR_H
#define DESFIRE_EMULATOR_H

#include <Arduino.h>

class DESFireEmulator {
public:
    DESFireEmulator();
    
    // Initialize the emulator with EML string data
    bool loadEML(const String& emlData);
    
    // Process an incoming APDU and generate a response
    // rxBuffer: incoming APDU
    // rxLen: length of incoming APDU
    // txBuffer: buffer to store response APDU
    // Returns: length of response APDU
    int processAPDU(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer);
    
private:
    // State machine variables
    uint32_t currentAID;
    bool isAuthenticated;
    uint8_t sessionKey[16];
    
    // Command Handlers
    int handleSelectApplication(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer);
    int handleGetApplicationIDs(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer);
    int handleAuthenticate(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer);
    int handleReadData(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer);
};

#endif // DESFIRE_EMULATOR_H
