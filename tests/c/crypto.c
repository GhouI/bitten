#include "darwin.h"

typedef struct { uint32_t words[23]; } md5_ctx;
typedef struct { uint32_t words[24]; } sha1_ctx;
typedef struct { uint32_t words[26]; } sha256_ctx;
typedef struct { uint64_t words[26]; } sha512_ctx;
typedef struct { uint32_t words[96]; } hmac_ctx;

_Static_assert(sizeof(md5_ctx) == 92, "MD5 context");
_Static_assert(sizeof(sha1_ctx) == 96, "SHA-1 context");
_Static_assert(sizeof(sha256_ctx) == 104, "SHA-224/256 context");
_Static_assert(sizeof(sha512_ctx) == 208, "SHA-384/512 context");
_Static_assert(sizeof(hmac_ctx) == 384, "HMAC context");

#define DECLARE(name, type)                                \
    uint8_t *name(const void *, uint32_t, uint8_t *);       \
    int name##_Init(type *);                               \
    int name##_Update(type *, const void *, uint32_t);      \
    int name##_Final(uint8_t *, type *)

DECLARE(CC_MD5, md5_ctx);
DECLARE(CC_SHA1, sha1_ctx);
DECLARE(CC_SHA224, sha256_ctx);
DECLARE(CC_SHA256, sha256_ctx);
DECLARE(CC_SHA384, sha512_ctx);
DECLARE(CC_SHA512, sha512_ctx);

void CCHmac(uint32_t, const void *, size_t, const void *, size_t, void *);
void CCHmacInit(hmac_ctx *, uint32_t, const void *, size_t);
void CCHmacUpdate(hmac_ctx *, const void *, size_t);
void CCHmacFinal(hmac_ctx *, void *);
int CCKeyDerivationPBKDF(uint32_t, const char *, size_t, const uint8_t *, size_t, uint32_t,
                         unsigned, uint8_t *, size_t);
unsigned CCCalibratePBKDF(uint32_t, size_t, size_t, uint32_t, size_t, uint32_t);
int CCRandomGenerateBytes(void *, size_t);
extern const void *kSecRandomDefault;
int SecRandomCopyBytes(const void *, size_t, void *);

typedef struct cryptor *cc_ref;
int CCCryptorCreate(uint32_t, uint32_t, uint32_t, const void *, size_t, const void *, cc_ref *);
int CCCryptorCreateWithMode(uint32_t, uint32_t, uint32_t, uint32_t, const void *, const void *,
                           size_t, const void *, size_t, int, uint32_t, cc_ref *);
int CCCryptorUpdate(cc_ref, const void *, size_t, void *, size_t, size_t *);
int CCCryptorFinal(cc_ref, void *, size_t, size_t *);
int CCCryptorRelease(cc_ref);
int CCCryptorReset(cc_ref, const void *);
size_t CCCryptorGetOutputLength(cc_ref, size_t, _Bool);
int CCCrypt(uint32_t, uint32_t, uint32_t, const void *, size_t, const void *, const void *, size_t,
            void *, size_t, size_t *);
int CCCryptorGCMOneshotEncrypt(uint32_t, const void *, size_t, const void *, size_t, const void *,
                               size_t, const void *, size_t, void *, void *, size_t);
int CCCryptorGCMOneshotDecrypt(uint32_t, const void *, size_t, const void *, size_t, const void *,
                               size_t, const void *, size_t, void *, const void *, size_t);
int CCCryptorGCM(uint32_t, uint32_t, const void *, size_t, const void *, size_t, const void *,
                 size_t, const void *, size_t, void *, void *, size_t *);

static unsigned digit(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }

static size_t unhex(uint8_t *out, const char *s) {
    size_t size = strlen(s) / 2;
    for (size_t i = 0; i < size; i++) out[i] = (digit(s[2*i]) << 4) | digit(s[2*i+1]);
    return size;
}

static void expect(const uint8_t *out, const char *hex) {
    for (size_t i = 0; hex[2*i]; i++) {
        unsigned expected = (digit(hex[2*i]) << 4) | digit(hex[2*i+1]);
        if (out[i] != expected) {
            printf("Vector %s, byte %lu: expected %02x, got %02x\n", hex, i, expected, (unsigned)out[i]);
            exit(1);
        }
    }
}

static void md5_tests(void) {
    static const struct { const char *text, *hex; } cases[] = {
        {"", "d41d8cd98f00b204e9800998ecf8427e"},
        {"a", "0cc175b9c0f1b6a831c399e269772661"},
        {"abc", "900150983cd24fb0d6963f7d28e17f72"},
        {"message digest", "f96b697d7cb7938d525a2f31aaf161d0"},
        {"abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"},
        {"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "d174ab98d277d9f5a5611c2c9f419d9f"},
        {"12345678901234567890123456789012345678901234567890123456789012345678901234567890",
         "57edf4a22be3c955ac49da2e2107b67a"},
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        uint8_t out[16];
        CHECK(CC_MD5(cases[i].text, strlen(cases[i].text), out) == out);
        expect(out, cases[i].hex);
        struct { md5_ctx ctx; uint32_t guard; } c = {.guard = 1234};
        CHECK(CC_MD5_Init(&c.ctx) == 1);
        for (size_t n = 0; cases[i].text[n]; n++)
            CHECK(CC_MD5_Update(&c.ctx, cases[i].text + n, 1) == 1);
        CHECK(CC_MD5_Final(out, &c.ctx) == 1 && c.guard == 1234);
        expect(out, cases[i].hex);
    }
}

static void sha_tests(void) {
    static const char long_message[] =
        "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
        "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
    _Static_assert(sizeof long_message == 113, "896-bit test input");
    const char *messages[] = {"", "abc", long_message};
    uint8_t out[64];
    char payload[113];
    memset(payload, 'a', sizeof payload);
    static const char *const hashes[5][4] = {
        {
            "da39a3ee5e6b4b0d3255bfef95601890afd80709",
            "a9993e364706816aba3e25717850c26c9cd0d89d",
            "a49b2446a02c645bf419f995b67091253a04a259",
            "34aa973cd4c4daa4f61eeb2bdbad27316534016f",
        },
        {
            "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f",
            "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
            "c97ca9a559850ce97a04a96def6d99a9e0e0e2ab14e6b8df265fc0b3",
            "20794655980c91d8bbb4c1ea97618a4bf03f42581948b2ee4ee7ad67",
        },
        {
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
        },
        {
            "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da"
            "274edebfe76f65fbd51ad2f14898b95b",
            "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
            "8086072ba1e7cc2358baeca134c825a7",
            "09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712"
            "fcc7c71a557e2db966c3e9fa91746039",
            "9d0e1809716474cb086e834e310a4a1ced149e9c00f248527972cec5704c2a5b"
            "07b8b3dc38ecc4ebae97ddd87f3d8985",
        },
        {
            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
            "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
            "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
            "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018"
            "501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909",
            "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973eb"
            "de0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b",
        },
    };

#define RUN_SHA(name, type, row) do {                                                     \
    struct { type ctx; uint64_t guard; } c = {.guard = 1234};                            \
    for (unsigned i = 0; i < 3; i++) {                                                   \
        CHECK(name(messages[i], strlen(messages[i]), out) == out);                      \
        expect(out, hashes[row][i]);                                                     \
    }                                                                                    \
    CHECK(name##_Init(&c.ctx) == 1);                                                      \
    size_t left = 1000000;                                                               \
    while (left) {                                                                       \
        size_t n = left < sizeof payload ? left : sizeof payload;                      \
        CHECK(name##_Update(&c.ctx, payload, n) == 1);                                   \
        left -= n;                                                                       \
    }                                                                                    \
    CHECK(name##_Final(out, &c.ctx) == 1 && c.guard == 1234);                              \
    expect(out, hashes[row][3]);                                                         \
} while (0)
    RUN_SHA(CC_SHA1, sha1_ctx, 0);
    RUN_SHA(CC_SHA224, sha256_ctx, 1);
    RUN_SHA(CC_SHA256, sha256_ctx, 2);
    RUN_SHA(CC_SHA384, sha512_ctx, 3);
    RUN_SHA(CC_SHA512, sha512_ctx, 4);
}

static void test_hmac(unsigned alg, const void *key, size_t len, const char *text, const char *hex) {
    uint8_t out[64];
    size_t n = strlen(text);
    CCHmac(alg, key, len, text, n, out);
    expect(out, hex);
    struct { uint32_t lead; hmac_ctx ctx; uint32_t end; } c = {.lead = 17, .end = 1234};
    CCHmacInit(&c.ctx, alg, key, len);
    for (size_t i = 0; i < n; i++) CCHmacUpdate(&c.ctx, text + i, 1);
    CCHmacFinal(&c.ctx, out);
    CHECK(c.lead == 17 && c.end == 1234);
    expect(out, hex);
}

static void hmac_tests(void) {
    uint8_t key[131];
    memset(key, 0x0b, sizeof key);
    test_hmac(0, key, 20, "Hi There",
              "b617318655057264e28bc0b6fb378c8ef146be00");
    test_hmac(1, key, 16, "Hi There",
              "9294727a3638bb1c13f48ef8158bfc9d");
    test_hmac(2, key, 20, "Hi There",
              "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
    test_hmac(3, key, 20, "Hi There",
              "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59c"
              "faea9ea9076ede7f4af152e8b2fa9cb6");
    test_hmac(4, key, 20, "Hi There",
              "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde"
              "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854");
    test_hmac(5, key, 20, "Hi There",
              "896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22");
    test_hmac(0, "Jefe", 4, "what do ya want for nothing?", "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79");
    memset(key, 0xaa, sizeof key);
    test_hmac(2, key, sizeof key, "Test Using Larger Than Block-Size Key - Hash Key First",
              "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
}

static void aes_tests(void) {
    static const char *const keys[] = {
        "2b7e151628aed2a6abf7158809cf4f3c",
        "8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b",
        "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4",
    };
    static const char *const ecb[] = {
        "3ad77bb40d7a3660a89ecaf32466ef97", "bd334f1d6e45f25ff712a214571fa5cc", "f3eed1bdb5d2a03c064b5a7e3db181f8",
    };
    static const char *const cbc[] = {
        "7649abac8119b246cee98e9b12e9197d", "4f021db243bc633d7178183a9fa071e8", "f58c4c04d6e5f1ba779eabfb5f7bfbd6",
    };
    static const char *const ctr[] = {
        "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff",
        "1abc932417521ca24f2b0459fe7e6e0b090339ec0aa6faefd5ccc2c6f4ce8e94",
        "601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5",
    };
    static const char *const fips[] = {
        "69c4e0d86a7b0430d8cdb78070b4c55a", "dda97ca4864cdfe06eaf70a0ec0d7191", "8ea2b7ca516745bfeafc49904b496089",
    };
    uint8_t key[32], input[32], other[16], iv[16], counter[16], out[32], decoded[32];
    unhex(input, "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51");
    unhex(other, "00112233445566778899aabbccddeeff");
    for (unsigned i = 0; i < 16; i++) { iv[i] = i; counter[i] = 240 + i; }
    for (unsigned i = 0; i < 3; i++) {
        size_t n = 16 + 8*i, moved;
        for (unsigned j = 0; j < n; j++) key[j] = j;
        CHECK(CCCrypt(0, 0, 2, key, n, NULL, other, 16, out, sizeof out, &moved) == 0 && moved == 16);
        expect(out, fips[i]);
        CHECK(unhex(key, keys[i]) == n);
        for (unsigned mode = 0; mode <= 2; mode += 2) {
            CHECK(CCCrypt(0, 0, mode, key, n, iv, input, 16, out, sizeof out, &moved) == 0 && moved == 16);
            expect(out, mode ? ecb[i] : cbc[i]);
            CHECK(CCCrypt(1, 0, mode, key, n, iv, out, 16, out, sizeof out, &moved) == 0 && moved == 16);
            CHECK(memcmp(out, input, 16) == 0);
        }
        cc_ref ref;
        CHECK(CCCryptorCreateWithMode(0, 4, 0, 0, counter, key, n, NULL, 0, 0, 2, &ref) == 0);
        CHECK(CCCryptorUpdate(ref, input, 7, out, 7, &moved) == 0 && moved == 7);
        CHECK(CCCryptorUpdate(ref, input + 7, 25, out + 7, 25, &moved) == 0 && moved == 25);
        CHECK(CCCryptorFinal(ref, NULL, 0, &moved) == 0 && moved == 0);
        expect(out, ctr[i]);
        CHECK(CCCryptorReset(ref, counter) == 0);
        CHECK(CCCryptorUpdate(ref, out, sizeof out, decoded, sizeof decoded, &moved) == 0 && moved == 32);
        CHECK(memcmp(decoded, input, sizeof input) == 0);
        CHECK(CCCryptorRelease(ref) == 0);
    }
    size_t moved;
    CHECK(CCCrypt(0, 0, 0, key, 15, iv, input, 16, out, sizeof out, &moved) == -4300);
    CHECK(CCCrypt(0, 1, 0, key, 16, iv, input, 16, out, sizeof out, &moved) == -4305);
    CHECK(CCCrypt(0, 0, 0, key, 16, iv, input, 15, out, sizeof out, &moved) == -4303);
    CHECK(CCCrypt(0, 0, 1, key, 16, iv, input, 16, out, 31, &moved) == -4301 && moved == 32);
}

static size_t padded(uint32_t op, uint32_t options, const uint8_t *key, const uint8_t *iv,
                     const uint8_t *in, size_t n, uint8_t *out) {
    cc_ref ref;
    CHECK(CCCryptorCreate(op, 0, options, key, 16, iv, &ref) == 0);
    size_t used = 0;
    while (n) {
        size_t take = n < 7 ? n : 7, moved;
        size_t expected = CCCryptorGetOutputLength(ref, take, 0);
        if (expected) CHECK(CCCryptorUpdate(ref, in, take, out + used, expected - 1, &moved) == -4301);
        CHECK(CCCryptorUpdate(ref, in, take, out + used, expected, &moved) == 0 && moved == expected);
        used += moved;
        in += take;
        n -= take;
    }
    size_t moved;
    if (!op) CHECK(CCCryptorFinal(ref, out + used, 15, &moved) == -4301);
    CHECK(CCCryptorFinal(ref, out + used, CCCryptorGetOutputLength(ref, 0, 1), &moved) == 0);
    CHECK(CCCryptorRelease(ref) == 0);
    return used + moved;
}

static void padding_tests(void) {
    uint8_t key[16] = {0}, iv[16] = {1}, input[48], out[64], decoded[64], compare[64];
    for (unsigned i = 0; i < sizeof input; i++) input[i] = 3*i;
    for (uint32_t options = 1; options <= 3; options += 2) {
        for (size_t n = 0; n <= sizeof input; n++) {
            size_t size = padded(0, options, key, iv, input, n, out), moved;
            CHECK(size == n - n % 16 + 16);
            CHECK(CCCrypt(0, 0, options, key, 16, iv, input, n, compare, sizeof compare, &moved) == 0);
            CHECK(moved == size && memcmp(compare, out, size) == 0);
            CHECK(padded(1, options, key, iv, out, size, decoded) == n);
            CHECK(memcmp(decoded, input, n) == 0);
            CHECK(CCCrypt(1, 0, options, key, 16, iv, out, size, decoded, n, &moved) == 0 && moved == n);
        }
    }
    size_t moved;
    CHECK(CCCrypt(0, 0, 2, key, 16, iv, key, 16, out, 16, &moved) == 0);
    CHECK(CCCrypt(1, 0, 3, key, 16, iv, out, 16, decoded, 16, &moved) == -4304);
}

static void gcm_tests(void) {
    uint8_t key[16] = {0}, nonce[12] = {0}, data[64] = {0}, cipher[64], out[64], tag[16], aad[20];
    CHECK(CCCryptorGCMOneshotEncrypt(0, key, 16, nonce, 12, NULL, 0, data, 16, cipher, tag, 16) == 0);
    expect(cipher, "0388dace60b6a392f328c2b971b2fe78");
    expect(tag, "ab6e47d42cec13bdf53a67b21257bddf");
    unhex(key, "feffe9928665731c6d6a8f9467308308");
    unhex(nonce, "cafebabefacedbaddecaf888");
    unhex(aad, "feedfacedeadbeeffeedfacedeadbeefabaddad2");
    size_t n = unhex(data, "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
                            "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39");
    CHECK(CCCryptorGCMOneshotEncrypt(0, key, 16, nonce, 12, aad, 20, data, n, cipher, tag, 16) == 0);
    expect(cipher, "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e"
                   "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091");
    expect(tag, "5bc94fbc3221a5db94fae95ae7121a47");
    CHECK(CCCryptorGCMOneshotDecrypt(0, key, 16, nonce, 12, aad, 20, cipher, n, out, tag, 16) == 0);
    CHECK(memcmp(out, data, n) == 0);
    size_t taglen = 16;
    memset(out, 0, sizeof out);
    CHECK(CCCryptorGCM(1, 0, key, 16, nonce, 12, aad, 20, cipher, n, out, tag, &taglen) == 0);
    CHECK(taglen == 16 && memcmp(out, data, n) == 0);
    expect(tag, "5bc94fbc3221a5db94fae95ae7121a47");
    tag[0] ^= 1;
    memset(out, 0xab, sizeof out);
    CHECK(CCCryptorGCMOneshotDecrypt(0, key, 16, nonce, 12, aad, 20, cipher, n, out, tag, 16) == -4304);
    for (size_t i = 0; i < n; i++) CHECK(out[i] == 0xab);
    CHECK(CCCryptorGCM(0, 0, key, 16, nonce, 8, aad, 20, data, n, cipher, tag, &taglen) == 0);
    expect(cipher, "61353b4c2806934a777ff51fa22a4755699b2a714fcdc6f83766e5f97b6c7423"
                   "73806900e49f24b22b097544d4896b424989b5e1ebac0f07c23f4598");
    expect(tag, "3612d2e79e3b0785561be14aaca2fccb");
}

static void kdf_random_tests(void) {
    uint8_t out[64], random[64];
    CHECK(CCKeyDerivationPBKDF(2, "password", 8, (const uint8_t *)"salt", 4, 1, 1, out, 20) == 0);
    expect(out, "0c60c80f961f0e71f3a9b524af6012062fe037a6");
    CHECK(CCKeyDerivationPBKDF(2, "password", 8, (const uint8_t *)"salt", 4, 1, 4096, out, 20) == 0);
    expect(out, "4b007901b765489abead49d926f721d065a429c1");
    CHECK(CCKeyDerivationPBKDF(2, "pass\0word", 9, (const uint8_t *)"sa\0lt", 5, 1, 4096, out, 16) == 0);
    expect(out, "56fa6aa75548099dcc37d7f03425e0c3");
    CHECK(CCKeyDerivationPBKDF(2, "password", 8, (const uint8_t *)"salt", 4, 3, 2, out, 32) == 0);
    expect(out, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43");
    CHECK(CCCalibratePBKDF(2, 8, 4, 3, 32, 100) > 0);
    CHECK(CCRandomGenerateBytes(out, sizeof out) == 0);
    CHECK(kSecRandomDefault == NULL);
    CHECK(SecRandomCopyBytes(kSecRandomDefault, sizeof random, random) == 0);
    CHECK(memcmp(out, random, sizeof out) != 0);
}

int main(void) {
    md5_tests();
    sha_tests();
    hmac_tests();
    aes_tests();
    padding_tests();
    gcm_tests();
    kdf_random_tests();
    puts("crypto ok");
    return 0;
}
