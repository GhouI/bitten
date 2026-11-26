/* bitten SDK: Security's TLS protocol versions and cipher suites, as
 * URLSession's transaction metrics report them. */
#ifndef BITTEN_SEC_PROTOCOL_TYPES_H
#define BITTEN_SEC_PROTOCOL_TYPES_H
#include <stdint.h>

typedef enum tls_protocol_version_t : uint16_t {
    tls_protocol_version_TLSv10 __attribute__((swift_name("tls_protocol_version_t.TLSv10"))) = 0x0301,
    tls_protocol_version_TLSv11 __attribute__((swift_name("tls_protocol_version_t.TLSv11"))) = 0x0302,
    tls_protocol_version_TLSv12 __attribute__((swift_name("tls_protocol_version_t.TLSv12"))) = 0x0303,
    tls_protocol_version_TLSv13 __attribute__((swift_name("tls_protocol_version_t.TLSv13"))) = 0x0304,
    tls_protocol_version_DTLSv10 __attribute__((swift_name("tls_protocol_version_t.DTLSv10"))) = 0xfeff,
    tls_protocol_version_DTLSv12 __attribute__((swift_name("tls_protocol_version_t.DTLSv12"))) = 0xfefd,
} tls_protocol_version_t;

typedef enum tls_ciphersuite_t : uint16_t {
    tls_ciphersuite_RSA_WITH_AES_128_GCM_SHA256 __attribute__((swift_name("tls_ciphersuite_t.RSA_WITH_AES_128_GCM_SHA256"))) = 0x009C,
    tls_ciphersuite_RSA_WITH_AES_256_GCM_SHA384 __attribute__((swift_name("tls_ciphersuite_t.RSA_WITH_AES_256_GCM_SHA384"))) = 0x009D,
    tls_ciphersuite_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"))) = 0xC02B,
    tls_ciphersuite_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"))) = 0xC02C,
    tls_ciphersuite_ECDHE_RSA_WITH_AES_128_GCM_SHA256 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_RSA_WITH_AES_128_GCM_SHA256"))) = 0xC02F,
    tls_ciphersuite_ECDHE_RSA_WITH_AES_256_GCM_SHA384 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_RSA_WITH_AES_256_GCM_SHA384"))) = 0xC030,
    tls_ciphersuite_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"))) = 0xCCA8,
    tls_ciphersuite_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 __attribute__((swift_name("tls_ciphersuite_t.ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"))) = 0xCCA9,
    tls_ciphersuite_AES_128_GCM_SHA256 __attribute__((swift_name("tls_ciphersuite_t.AES_128_GCM_SHA256"))) = 0x1301,
    tls_ciphersuite_AES_256_GCM_SHA384 __attribute__((swift_name("tls_ciphersuite_t.AES_256_GCM_SHA384"))) = 0x1302,
    tls_ciphersuite_CHACHA20_POLY1305_SHA256 __attribute__((swift_name("tls_ciphersuite_t.CHACHA20_POLY1305_SHA256"))) = 0x1303,
} tls_ciphersuite_t;
#endif
