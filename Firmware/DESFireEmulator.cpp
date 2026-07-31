#include "DESFireEmulator.h"

DESFireEmulator::DESFireEmulator() {
    currentAID = 0x000000;
    isAuthenticated = false;
}

bool DESFireEmulator::loadEML(const String& emlData) {
    // Basic scaffold for EML loading
    // In a full implementation, this parses AIDs, Keys, and File contents from the text.
    currentAID = 0x000000;
    isAuthenticated = false;
    return true;
}

int DESFireEmulator::processAPDU(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer) {
    if (rxLen < 1) return 0;
    
    uint8_t cmd = rxBuffer[0];
    int txLen = 0;
    
    switch (cmd) {
        case 0x5A: // Select Application
            txLen = handleSelectApplication(rxBuffer, rxLen, txBuffer);
            break;
        case 0x6A: // Get Application IDs
            txLen = handleGetApplicationIDs(rxBuffer, rxLen, txBuffer);
            break;
        case 0x0A: // Authenticate Native
        case 0x1A: // Authenticate ISO
        case 0xAA: // Authenticate AES
            txLen = handleAuthenticate(rxBuffer, rxLen, txBuffer);
            break;
        case 0xBD: // Read Data
            txLen = handleReadData(rxBuffer, rxLen, txBuffer);
            break;
        default:
            // Unsupported command
            txBuffer[0] = 0x1C; // ILLEGAL_COMMAND
            txLen = 1;
            break;
    }
    
    return txLen;
}

int DESFireEmulator::handleSelectApplication(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer) {
    if (rxLen < 4) {
        txBuffer[0] = 0x7E; // LENGTH_ERROR
        return 1;
    }
    
    // DESFire AIDs are 3 bytes, little endian in the command
    currentAID = (rxBuffer[3] << 16) | (rxBuffer[2] << 8) | rxBuffer[1];
    isAuthenticated = false; // Selecting an app resets auth
    
    txBuffer[0] = 0x00; // OPERATION_OK
    return 1;
}

int DESFireEmulator::handleGetApplicationIDs(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer) {
    // Return dummy AID 0x123456
    txBuffer[0] = 0x56;
    txBuffer[1] = 0x34;
    txBuffer[2] = 0x12;
    txBuffer[3] = 0x00; // OPERATION_OK status appended at the end usually, or just 0x00 if nothing else
    // Actually DESFire returns data then status byte. 
    // Data: 56 34 12, Status: 00
    // So txBuffer[0..2] = AID, txBuffer[3] = 0x00
    return 4;
}

int DESFireEmulator::handleAuthenticate(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer) {
    // Authentication is a multi-step process. 
    // Step 1: PICC sends enciphered RndB.
    txBuffer[0] = 0xAF; // ADDITIONAL_FRAME
    // (Dummy RndB for scaffold)
    for (int i=1; i<=16; i++) txBuffer[i] = i; 
    return 17;
}

int DESFireEmulator::handleReadData(const uint8_t* rxBuffer, int rxLen, uint8_t* txBuffer) {
    // Read Data (0xBD) requires FileNo, Offset (3 bytes), Length (3 bytes)
    // For scaffold, just return some dummy data.
    txBuffer[0] = 0x11;
    txBuffer[1] = 0x22;
    txBuffer[2] = 0x33;
    txBuffer[3] = 0x00; // OPERATION_OK
    return 4;
}
