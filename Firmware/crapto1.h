#ifndef CRAPTO1_H
#define CRAPTO1_H

#include <stdint.h>

struct crypto1_state {
    uint32_t odd;
    uint32_t even;
};

void crypto1_init(struct crypto1_state *state, uint64_t key);
uint8_t crypto1_bit(struct crypto1_state *state, uint8_t in, int is_encrypted);
uint8_t crypto1_byte(struct crypto1_state *state, uint8_t in, int is_encrypted);
uint32_t crypto1_word(struct crypto1_state *state, uint32_t in, int is_encrypted);

#endif
