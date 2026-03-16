// Minimal FFI wrapper around the argon2 reference C implementation.
// Calls argon2id_hash_raw directly and returns raw bytes (no base64).

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "argon2/argon2.h"

// Returns 0 on success, non-zero argon2 error code on failure.
// `out` must point to a buffer of at least `hashlen` bytes.
__attribute__((visibility("default")))
int moor_argon2id_hash(
    const uint8_t *pwd, uint32_t pwdlen,
    const uint8_t *salt, uint32_t saltlen,
    uint32_t t_cost,
    uint32_t m_cost,
    uint32_t parallelism,
    uint8_t *out, uint32_t hashlen
) {
    return argon2id_hash_raw(
        t_cost, m_cost, parallelism,
        pwd, pwdlen,
        salt, saltlen,
        out, hashlen
    );
}
