/* LZFSE and LZVN (lzfse.c). Each returns the bytes written, 0 on error. */
#ifndef BITTEN_LZFSE_H
#define BITTEN_LZFSE_H
#include <stddef.h>
#include <stdint.h>
size_t bn_lzfse_decode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n);
size_t bn_lzfse_decoded_size(const uint8_t *src, size_t n);
size_t bn_lzfse_encode(uint8_t *dst, size_t cap, const uint8_t *src, size_t n);
#endif
