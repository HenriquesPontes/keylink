# MIFARE Classic Auth Flow
- Tag sends `nT`
- Reader sends `nR_enc` and `aR_enc`
- Tag receives `nR_enc`, absorbs it: `crypto1_word(&crypto1, nr_enc, 1)`
- Tag decrypts `aR_enc` (advances cipher 4 bytes): `crypto1_word(&crypto1, ar_enc, 0)` (Wait, we can just decrypt 0 to get the keystream for aR, or we can just step it? `crypto1_word` steps it.)
- Tag encrypts `aT` (advances cipher 4 bytes): `at_enc = crypto1_word(&crypto1, at_plain, 0)`

Let's check.
