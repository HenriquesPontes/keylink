#ifndef DESFIRE_CRYPTO_H
#define DESFIRE_CRYPTO_H

#include <Arduino.h>
#include <mbedtls/aes.h>
#include <mbedtls/des.h>

class DESFireCrypto {
public:
    DESFireCrypto();
    
    // Encrypt data with AES
    void encryptAES(const uint8_t* key, const uint8_t* iv, const uint8_t* input, uint8_t* output, size_t length);
    
    // Decrypt data with AES
    void decryptAES(const uint8_t* key, const uint8_t* iv, const uint8_t* input, uint8_t* output, size_t length);
    
    // Calculate CMAC
    void calculateCMAC(const uint8_t* key, const uint8_t* input, size_t length, uint8_t* mac);
    
    // Generate Session Key based on RndA and RndB
    void generateSessionKey(const uint8_t* rndA, const uint8_t* rndB, uint8_t* sessionKey);
};

#endif // DESFIRE_CRYPTO_H
