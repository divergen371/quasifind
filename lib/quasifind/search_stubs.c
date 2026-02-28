/* search_stubs.c - Mmap based regex search with optional SIMD acceleration */

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <regex.h>
#include <string.h>
#include <errno.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>
#include <caml/signals.h>

/* ═══════════════════════════════════════════════════════════════════════════
   ARM NEON SIMD-accelerated memmem
   ═══════════════════════════════════════════════════════════════════════════ */

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>

/*
   neon_extract_mask: Convert a NEON comparison result (0x00/0xFF per byte)
   into a 16-bit mask where each bit represents whether the corresponding
   byte matched.
*/
static inline uint16_t neon_extract_mask(uint8x16_t v)
{
    /* Shift each byte to isolate the high bit, then narrow and combine */
    static const uint8x16_t shift = {0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7};
    uint8x16_t masked = vshrq_n_u8(v, 7); /* 0x00 or 0x01 per lane */
    uint8x16_t shifted = vshlq_u8(masked, vreinterpretq_s8_u8(shift));
    /* Sum the low 8 and high 8 lanes separately */
    uint8_t lo = vaddv_u8(vget_low_u8(shifted));
    /* vget_high returns uint8x8_t, use vaddv_u8 (not vaddvq_u8) */
    uint8x8_t hi_half = vget_high_u8(shifted);
    uint8_t hi = vaddv_u8(hi_half);
    return (uint16_t)lo | ((uint16_t)hi << 8);
}

/*
   simd_memmem_neon: SIMD-accelerated string search using ARM NEON.

   Algorithm:
   1. Broadcast needle[0] and needle[nlen-1] to all 16 NEON lanes
   2. For each 16-byte aligned chunk of haystack:
      a. Compare chunk[i] == needle[0] AND chunk[i+nlen-1] == needle[nlen-1]
      b. Extract a bitmask of matching positions
      c. For each match, verify with memcmp

   This "first+last" trick dramatically reduces false positives compared
   to single-byte scanning, especially for longer needles.
*/
static void *simd_memmem_neon(const void *haystack, size_t hlen,
                              const void *needle, size_t nlen)
{
    if (nlen == 0)
        return (void *)haystack;
    if (nlen > hlen)
        return NULL;

    const uint8_t *h = (const uint8_t *)haystack;
    const uint8_t *n = (const uint8_t *)needle;
    size_t end = hlen - nlen;

    /* Single byte needle: just use memchr */
    if (nlen == 1)
    {
        return memchr(haystack, n[0], hlen);
    }

    /* Broadcast first and last bytes of needle to all 16 lanes */
    uint8x16_t first = vdupq_n_u8(n[0]);
    uint8x16_t last = vdupq_n_u8(n[nlen - 1]);

    size_t i = 0;

    /* Process 16 bytes at a time */
    for (; i + 15 + nlen - 1 <= hlen; i += 16)
    {
        /* Load 16 bytes starting at position i (first byte candidates) */
        uint8x16_t block_first = vld1q_u8(h + i);
        /* Load 16 bytes starting at position i+nlen-1 (last byte candidates) */
        uint8x16_t block_last = vld1q_u8(h + i + nlen - 1);

        /* Compare: which positions have matching first AND last byte? */
        uint8x16_t eq_first = vceqq_u8(block_first, first);
        uint8x16_t eq_last = vceqq_u8(block_last, last);
        uint8x16_t eq = vandq_u8(eq_first, eq_last);

        /* Quick check: any matches at all? */
        if (vmaxvq_u8(eq) == 0)
            continue;

        /* Extract bitmask and check each candidate */
        uint16_t mask = neon_extract_mask(eq);
        while (mask != 0)
        {
            int bit = __builtin_ctz(mask);
            size_t pos = i + bit;
            if (pos <= end && memcmp(h + pos, n, nlen) == 0)
            {
                return (void *)(h + pos);
            }
            mask &= mask - 1; /* Clear lowest set bit */
        }
    }

    /* Handle remaining bytes with scalar fallback */
    for (; i <= end; i++)
    {
        if (h[i] == n[0] && memcmp(h + i, n, nlen) == 0)
        {
            return (void *)(h + i);
        }
    }

    return NULL;
}
/* ═══════════════════════════════════════════════════════════════════════════
   Lightweight Aho-Corasick / KMP + BMH + NEON hybrid search

   Total footprint: ~520 bytes (vs 263KB for full AC goto table)
   - Pattern pointer + length
   - KMP failure table (max 256 ints)
   - BMH skip table (256 ints)
   ═══════════════════════════════════════════════════════════════════════════ */

#define AC_MAX_PATTERN 256

typedef struct
{
    const uint8_t *pattern;
    size_t plen;
    int fail[AC_MAX_PATTERN]; /* KMP failure table */
    int skip[256];            /* BMH skip table */
} ac_lite_t;

static void ac_lite_build(ac_lite_t *ac, const uint8_t *pattern, size_t plen)
{
    ac->pattern = pattern;
    ac->plen = plen;

    /* KMP failure table */
    ac->fail[0] = -1;
    if (plen > 1)
    {
        ac->fail[1] = 0;
        for (size_t i = 2; i < plen && i < AC_MAX_PATTERN; i++)
        {
            int j = ac->fail[i - 1];
            while (j >= 0 && pattern[(size_t)j] != pattern[i - 1])
            {
                j = ac->fail[(size_t)j];
            }
            ac->fail[i] = j + 1;
        }
    }

    /* BMH skip table */
    for (int c = 0; c < 256; c++)
    {
        ac->skip[c] = (int)plen;
    }
    for (size_t i = 0; i + 1 < plen; i++)
    {
        ac->skip[pattern[i]] = (int)(plen - 1 - i);
    }
}

/*
   ac_lite_search_neon: NEON first+last trick + BMH scalar tail.
   Pattern bytes accessed directly (no goto table indirection).
*/
static void *ac_lite_search_neon(const ac_lite_t *ac,
                                 const void *haystack, size_t hlen)
{
    const uint8_t *h = (const uint8_t *)haystack;
    const uint8_t *p = ac->pattern;
    const size_t plen = ac->plen;

    if (plen == 0)
        return (void *)haystack;
    if (plen > hlen)
        return NULL;
    if (plen <= 3)
        return NULL; /* Signal: use simd_memmem_neon */

    const uint8_t first_byte = p[0];
    const uint8_t last_byte = p[plen - 1];
    const size_t end = hlen - plen;

    uint8x16_t vfirst = vdupq_n_u8(first_byte);
    uint8x16_t vlast = vdupq_n_u8(last_byte);

    size_t i = 0;

    /* NEON: check first+last byte simultaneously across 16 positions */
    for (; i + 15 + plen - 1 <= hlen; i += 16)
    {
        uint8x16_t eq_first = vceqq_u8(vld1q_u8(h + i), vfirst);
        uint8x16_t eq_last = vceqq_u8(vld1q_u8(h + i + plen - 1), vlast);
        uint8x16_t eq = vandq_u8(eq_first, eq_last);

        if (vmaxvq_u8(eq) == 0)
            continue;

        uint16_t mask = neon_extract_mask(eq);
        while (mask != 0)
        {
            int bit = __builtin_ctz(mask);
            size_t pos = i + (size_t)bit;
            if (pos <= end && memcmp(h + pos + 1, p + 1, plen - 2) == 0)
            {
                return (void *)(h + pos);
            }
            mask &= mask - 1;
        }
    }

    /* Scalar tail with BMH skip */
    size_t j = i + plen - 1;
    while (j < hlen)
    {
        if (h[j] != last_byte)
        {
            j += (size_t)ac->skip[h[j]];
            continue;
        }
        size_t start = j - (plen - 1);
        if (h[start] == first_byte && memcmp(h + start + 1, p + 1, plen - 2) == 0)
        {
            return (void *)(h + start);
        }
        j++;
    }

    return NULL;
}

#endif /* __ARM_NEON */

/*
   caml_search_regex(v_path, v_pattern)

   Returns:
     1 (true)  if pattern matches content
     0 (false) if pattern does not match
    -1 (error) if something went wrong (e.g. regex compilation failed, mmap failed)
               allowing fallback to OCaml implementation.
*/
CAMLprim value caml_search_regex(value v_path, value v_pattern)
{
    CAMLparam2(v_path, v_pattern);

#ifndef REG_STARTEND
    /* Without REG_STARTEND, we cannot safely use regexec on mmap'd data
       because the mapped region is not guaranteed to be null-terminated.
       We fail explicitly here to prevent out-of-bounds reads. */
    caml_failwith("Regex search on mmap requires REG_STARTEND support on this OS.");
#else
    const char *path = String_val(v_path);
    const char *pattern = String_val(v_pattern);
    int ret = 0;

    /* 1. Compile Regex */
    regex_t regex;
    /* Use REG_EXTENDED for modern syntax, REG_NOSUB for speed (we only care if it matches) */
    /* Note: macOS/BSD regex might differ slightly from GNU, hence fallback strategy is crucial. */
    if (regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB | REG_NEWLINE) != 0)
    {
        /* Regex compilation failed - likely unsupported syntax */
        CAMLreturn(Val_int(-1));
    }

    /* 2. Open File */
    int fd = open(path, O_RDONLY);
    if (fd == -1)
    {
        regfree(&regex);
        /* If file cannot be opened, we can't search it. Return -1 to let OCaml implementation handle it (or fail there). */
        CAMLreturn(Val_int(-1));
    }

    /* 3. Get file size */
    struct stat st;
    if (fstat(fd, &st) == -1)
    {
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(-1));
    }

    if (st.st_size == 0)
    {
        /* Empty file matches nothing usually, checks against empty string?
           Let's return 0 (no match) or check against empty buffer. */
        /* regexec on empty string: */
        int match = regexec(&regex, "", 0, NULL, 0);
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(match == 0 ? 1 : 0));
    }

    /* 4. Mmap */
    /* MAP_PRIVATE ensures we don't write back changes (though we are PROT_READ anyway) */
    void *addr = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (addr == MAP_FAILED)
    {
        close(fd);
        regfree(&regex);
        CAMLreturn(Val_int(-1));
    }

    /* 5. Execute Regex */
    /* We use REG_STARTEND to safely bound the search within the mmap'd size */
    regmatch_t pmatch[1];
    pmatch[0].rm_so = 0;
    pmatch[0].rm_eo = st.st_size;

    /* Release OCaml runtime lock while executing regex to allow other fibers/domains to proceed */
    caml_enter_blocking_section();
    int rc = regexec(&regex, (const char *)addr, 0, pmatch, REG_STARTEND);
    caml_leave_blocking_section();

    if (rc == 0)
    {
        ret = 1; /* Match */
    }
    else
    {
        ret = 0; /* No match (REG_NOMATCH) */
    }

    /* 6. Cleanup */
    munmap(addr, st.st_size);
    close(fd);
    regfree(&regex);

    CAMLreturn(Val_int(ret));
#endif
}

/*
   caml_search_memmem(v_path, v_needle)

   Fast literal string search using mmap + memmem.
   memmem on macOS/glibc uses SIMD-optimized routines internally.

   Returns:
     1 (true)  if needle is found in file content
     0 (false) if needle is not found
    -1 (error) if something went wrong
*/
CAMLprim value caml_search_memmem(value v_path, value v_needle)
{
    CAMLparam2(v_path, v_needle);
    const char *path = String_val(v_path);
    const char *needle = String_val(v_needle);
    mlsize_t needle_len = caml_string_length(v_needle);

    if (needle_len == 0)
    {
        /* Empty needle matches everything */
        CAMLreturn(Val_int(1));
    }

    /* 1. Open File */
    int fd = open(path, O_RDONLY);
    if (fd == -1)
    {
        CAMLreturn(Val_int(-1));
    }

    /* 2. Get file size */
    struct stat st;
    if (fstat(fd, &st) == -1 || st.st_size == 0)
    {
        close(fd);
        CAMLreturn(Val_int(st.st_size == 0 ? 0 : -1));
    }

    /* Skip files larger than 256MB to avoid excessive memory mapping */
    if (st.st_size > 256 * 1024 * 1024)
    {
        close(fd);
        CAMLreturn(Val_int(-1));
    }

    /* 3. Mmap */
    void *addr = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (addr == MAP_FAILED)
    {
        close(fd);
        CAMLreturn(Val_int(-1));
    }

    /* 4. Search - use SIMD-accelerated version on ARM, libc memmem elsewhere */
    caml_enter_blocking_section();
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    void *found = NULL;
    /* For patterns >= 4 bytes, try AC/KMP + NEON pre-filter */
    if (needle_len >= 4 && needle_len <= AC_MAX_PATTERN)
    {
        ac_lite_t ac;
        ac_lite_build(&ac, (const uint8_t *)needle, needle_len);
        found = ac_lite_search_neon(&ac, addr, st.st_size);
    }
    /* Fallback: NEON memmem (first+last trick) for short patterns or AC delegation */
    if (found == NULL && needle_len < 4)
    {
        found = simd_memmem_neon(addr, st.st_size, needle, needle_len);
    }
    /* Final fallback: simple NEON memmem if AC found nothing */
    if (found == NULL && needle_len >= 4)
    {
        found = simd_memmem_neon(addr, st.st_size, needle, needle_len);
    }
#else
    void *found = memmem(addr, st.st_size, needle, needle_len);
#endif
    caml_leave_blocking_section();
    
    int ret = (found != NULL) ? 1 : 0;

    /* 5. Cleanup */
    munmap(addr, st.st_size);
    close(fd);

    CAMLreturn(Val_int(ret));
}
