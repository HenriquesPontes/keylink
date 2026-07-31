#include "DESFireCrypto.h"
#include <string.h>

DESFireCrypto::DESFireCrypto() {
}

void DESFireCrypto::encryptAES(const uint8_t* key, const uint8_t* iv, const uint8_t* input, uint8_t* output, size_t length) {
    mbedtls_aes_context ctx;
    mbedtls_aes_init(&ctx);
    mbedtls_aes_setkey_enc(&ctx, key, 128);
    
    uint8_t iv_copy[16];
    memcpy(iv_copy, iv, 16);
    
    // mbedtls requires length to be a multiple of 16 for CBC
    mbedtls_aes_crypt_cbc(&ctx, MBEDTLS_AES_ENCRYPT, length, iv_copy, input, output);
    mbedtls_aes_free(&ctx);
}

void DESFireCrypto::decryptAES(const uint8_t* key, const uint8_t* iv, const uint8_t* input, uint8_t* output, size_t length) {
    mbedtls_aes_context ctx;
    mbedtls_aes_init(&ctx);
    mbedtls_aes_setkey_dec(&ctx, key, 128);
    
    uint8_t iv_copy[16];
    memcpy(iv_copy, iv, 16);
    
    mbedtls_aes_crypt_cbc(&ctx, MBEDTLS_AES_DECRYPT, length, iv_copy, input, output);
    mbedtls_aes_free(&ctx);
}

void DESFireCrypto::calculateCMAC(const uint8_t* key, const uint8_t* input, size_t length, uint8_t* mac) {
    // CMAC calculation requires mbedtls_cipher_cmac which is available if MBEDTLS_CMAC_C is defined.
    // For now, this is a scaffold that zeroes the MAC.
    memset(mac, 0, 16);
}

void DESFireCrypto::generateSessionKey(const uint8_t* rndA, const uint8_t* rndB, uint8_t* sessionKey) {
    // DESFire EV1/EV2 Session Key generation merges RndA and RndB.
    // Scaffold: just copy RndA and RndB halves.
    memcpy(sessionKey, rndA, 8);
    memcpy(sessionKey + 8, rndB, 8);
}
