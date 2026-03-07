const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("regex.h");
    @cInclude("string.h");
    @cInclude("caml/mlvalues.h");
    @cInclude("caml/memory.h");
    @cInclude("caml/alloc.h");
    @cInclude("caml/fail.h");
    @cInclude("caml/unixsupport.h");
    @cInclude("caml/signals.h");
});

inline fn String_val(v: c.value) [*c]const u8 {
    return @as([*c]const u8, @ptrFromInt(@as(usize, @bitCast(v))));
}

inline fn Int_val(v: c.value) c_int {
    return @as(c_int, @intCast(@as(isize, @bitCast(v)) >> 1));
}

inline fn Val_int(i: c_int) c.value {
    return @as(c.value, @bitCast((@as(isize, i) << 1) | 1));
}

// caml_string_length is a complex macro in OCaml, so we read the header safely in Zig.
inline fn caml_string_length(v: c.value) usize {
    // String length is stored in the header word before the string data.
    // OCaml string block: [header (8 bytes)] [chars...] [\0]
    // The last byte of the block contains padding info.
    // Since Zig is just linking against OCaml, we can rely on OCaml's caml_string_length macro if correctly imported,
    // but if it fails to compile, we implement it manually: Size of block - padding - 1.
    // Actually, `caml_string_length` function exists in OCaml 5 C API natively for simplicity, but let's see.
    return c.caml_string_length(v);
}

// SIMD memmem implementation
inline fn neon_extract_mask(v: @Vector(16, u8)) u16 {
    // We select bits per lane and sum.
    const bit_select = @Vector(16, u8){
        1, 2, 4, 8, 16, 32, 64, 128,
        1, 2, 4, 8, 16, 32, 64, 128,
    };
    const selected = v & bit_select;

    // Sum lower 8 and upper 8 bytes.
    const low_sum = @reduce(.Add, @as(@Vector(8, u8), @shuffle(u8, selected, undefined, @Vector(8, i32){ 0, 1, 2, 3, 4, 5, 6, 7 })));
    const high_sum = @reduce(.Add, @as(@Vector(8, u8), @shuffle(u8, selected, undefined, @Vector(8, i32){ 8, 9, 10, 11, 12, 13, 14, 15 })));

    return @as(u16, low_sum) | (@as(u16, high_sum) << 8);
}

fn simd_memmem_neon(haystack: [*]const u8, hlen: usize, needle: [*]const u8, nlen: usize) ?[*]const u8 {
    if (nlen == 0) return haystack;
    if (nlen > hlen) return null;

    if (nlen == 1) {
        if (c.memchr(haystack, needle[0], hlen)) |found| {
            return @as([*]const u8, @ptrCast(found));
        }
        return null;
    }

    const first_byte = needle[0];
    const last_byte = needle[nlen - 1];
    const end = hlen - nlen;

    const vfirst: @Vector(16, u8) = @splat(first_byte);
    const vlast: @Vector(16, u8) = @splat(last_byte);

    var i: usize = 0;

    // Unroll by 2 (32 bytes per loop iteration) with memory prefetch
    while (i + 31 + nlen - 1 <= hlen) : (i += 32) {
        // Prefetch 256 bytes ahead into L3 cache
        @prefetch(haystack + i + 256, .{ .rw = .read, .locality = 3, .cache = .data });

        comptime var u: usize = 0;
        inline while (u < 2) : (u += 1) {
            const offset = i + (u * 16);

            const block_first: @Vector(16, u8) = haystack[offset .. offset + 16][0..16].*;
            const block_last: @Vector(16, u8) = haystack[offset + nlen - 1 .. offset + nlen - 1 + 16][0..16].*;

            const eq_first = block_first == vfirst;
            const eq_last = block_last == vlast;

            const eq_first_u8 = @select(u8, eq_first, @as(@Vector(16, u8), @splat(0xFF)), @as(@Vector(16, u8), @splat(0x00)));
            const eq_last_u8 = @select(u8, eq_last, @as(@Vector(16, u8), @splat(0xFF)), @as(@Vector(16, u8), @splat(0x00)));
            const eq = eq_first_u8 & eq_last_u8;

            const max_val = @reduce(.Max, eq);
            if (max_val > 0) {
                var mask = neon_extract_mask(eq);
                while (mask != 0) {
                    const bit = @ctz(mask);
                    const pos = offset + bit;
                    if (pos <= end and c.memcmp(haystack + pos, needle, nlen) == 0) {
                        return haystack + pos;
                    }
                    mask &= mask - 1;
                }
            }
        }
    }

    while (i <= end) : (i += 1) {
        if (haystack[i] == first_byte and c.memcmp(haystack + i, needle, nlen) == 0) {
            return haystack + i;
        }
    }

    return null;
}

const AC_MAX_PATTERN = 256;
const ac_lite_t = struct {
    pattern: [*]const u8,
    plen: usize,
    fail: [AC_MAX_PATTERN]i32,
    skip: [256]i32,
};

fn ac_lite_build(ac: *ac_lite_t, pattern: [*]const u8, plen: usize) void {
    ac.pattern = pattern;
    ac.plen = plen;

    ac.fail[0] = -1;
    if (plen > 1) {
        ac.fail[1] = 0;
        var i: usize = 2;
        while (i < plen and i < AC_MAX_PATTERN) : (i += 1) {
            var j = ac.fail[i - 1];
            while (j >= 0 and pattern[@intCast(j)] != pattern[i - 1]) {
                j = ac.fail[@intCast(j)];
            }
            ac.fail[i] = j + 1;
        }
    }

    for (&ac.skip) |*s| {
        s.* = @intCast(plen);
    }
    var i: usize = 0;
    while (i + 1 < plen) : (i += 1) {
        ac.skip[pattern[i]] = @intCast(plen - 1 - i);
    }
}

fn ac_lite_search_neon(ac: *const ac_lite_t, haystack: [*]const u8, hlen: usize) ?[*]const u8 {
    const p = ac.pattern;
    const plen = ac.plen;

    if (plen == 0) return haystack;
    if (plen > hlen) return null;

    // Explicit Contract:
    // This function returns null for patterns of length <= 3.
    // Short patterns lack the requisite entropy for Aho-Corasick skips, making the
    // overhead of this function unjustifiable compared to the SIMD memmem fallback.
    // The caller (e.g., caml_search_memmem) MUST provide an alternative fallback mechanism
    // if this function yields null.
    if (plen <= 3) return null;

    const first_byte = p[0];
    const last_byte = p[plen - 1];
    const end = hlen - plen;

    const vfirst: @Vector(16, u8) = @splat(first_byte);
    const vlast: @Vector(16, u8) = @splat(last_byte);

    var i: usize = 0;

    while (i + 15 + plen - 1 <= hlen) : (i += 16) {
        const block_first: @Vector(16, u8) = haystack[i .. i + 16][0..16].*;
        const block_last: @Vector(16, u8) = haystack[i + plen - 1 .. i + plen - 1 + 16][0..16].*;

        const eq_first = block_first == vfirst;
        const eq_last = block_last == vlast;

        const eq_first_u8 = @select(u8, eq_first, @as(@Vector(16, u8), @splat(0xFF)), @as(@Vector(16, u8), @splat(0x00)));
        const eq_last_u8 = @select(u8, eq_last, @as(@Vector(16, u8), @splat(0xFF)), @as(@Vector(16, u8), @splat(0x00)));
        const eq = eq_first_u8 & eq_last_u8;

        const max_val = @reduce(.Max, eq);
        if (max_val > 0) {
            var mask = neon_extract_mask(eq);
            while (mask != 0) {
                const bit = @ctz(mask);
                const pos = i + bit;
                if (pos <= end and c.memcmp(haystack + pos + 1, p + 1, plen - 2) == 0) {
                    return haystack + pos;
                }
                mask &= mask - 1;
            }
        }
    }

    var j: usize = i + plen - 1;
    while (j < hlen) {
        if (haystack[j] != last_byte) {
            const skip_val = ac.skip[haystack[j]];
            j += @intCast(skip_val);
            continue;
        }
        const start = j - (plen - 1);
        if (haystack[start] == first_byte and c.memcmp(haystack + start + 1, p + 1, plen - 2) == 0) {
            return haystack + start;
        }
        j += 1;
    }

    return null;
}

export fn caml_search_regex(v_path: c.value, v_pattern: c.value) c.value {
    const path = String_val(v_path);
    const pattern = String_val(v_pattern);
    var ret: c_int = 0;

    var regex: c.regex_t = undefined;
    if (c.regcomp(&regex, pattern, c.REG_EXTENDED | c.REG_NOSUB | c.REG_NEWLINE) != 0) {
        return Val_int(-1);
    }

    const fd = c.open(path, c.O_RDONLY);
    if (fd == -1) {
        c.regfree(&regex);
        return Val_int(-1);
    }

    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == -1) {
        _ = c.close(fd);
        c.regfree(&regex);
        return Val_int(-1);
    }

    if (st.st_size == 0) {
        const match = c.regexec(&regex, "", 0, null, 0);
        _ = c.close(fd);
        c.regfree(&regex);
        return Val_int(if (match == 0) 1 else 0);
    }

    const addr = c.mmap(null, @intCast(st.st_size), c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (addr == c.MAP_FAILED) {
        _ = c.close(fd);
        c.regfree(&regex);
        return Val_int(-1);
    }

    var pmatch: [1]c.regmatch_t = undefined;
    pmatch[0].rm_so = 0;
    pmatch[0].rm_eo = st.st_size;

    c.caml_enter_blocking_section();
    // Use REG_STARTEND if available (macOS/BSD), otherwise fallback to null-terminated buffer (Linux)
    var rc: c_int = c.REG_NOMATCH;
    if (@hasDecl(c, "REG_STARTEND")) {
        rc = c.regexec(&regex, @ptrCast(addr), 0, &pmatch[0], c.REG_STARTEND);
    } else {
        const buf = c.malloc(@as(usize, @intCast(st.st_size)) + 1);
        if (buf != null) {
            const buf_ptr = @as([*c]u8, @ptrCast(buf));
            @memcpy(buf_ptr[0..@as(usize, @intCast(st.st_size))], @as([*]const u8, @ptrCast(addr))[0..@as(usize, @intCast(st.st_size))]);
            buf_ptr[@as(usize, @intCast(st.st_size))] = 0;
            rc = c.regexec(&regex, buf_ptr, 0, &pmatch[0], 0);
            c.free(buf);
        }
    }
    c.caml_leave_blocking_section();

    ret = if (rc == 0) 1 else 0;

    _ = c.munmap(addr, @intCast(st.st_size));
    _ = c.close(fd);
    c.regfree(&regex);

    return Val_int(ret);
}

export fn caml_search_memmem(v_path: c.value, v_needle: c.value) c.value {
    const path = String_val(v_path);
    const needle = String_val(v_needle);
    const needle_len = caml_string_length(v_needle);

    if (needle_len == 0) {
        return Val_int(1);
    }

    const fd = c.open(path, c.O_RDONLY);
    if (fd == -1) {
        return Val_int(-1);
    }

    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == -1) {
        _ = c.close(fd);
        return Val_int(-1);
    }
    if (st.st_size == 0) {
        _ = c.close(fd);
        return Val_int(0);
    }

    if (st.st_size > 256 * 1024 * 1024) {
        _ = c.close(fd);
        return Val_int(-1);
    }

    const addr = c.mmap(null, @intCast(st.st_size), c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (addr == c.MAP_FAILED) {
        _ = c.close(fd);
        return Val_int(-1);
    }

    c.caml_enter_blocking_section();
    const haystack = @as([*]const u8, @ptrCast(addr));
    const hlen = @as(usize, @intCast(st.st_size));
    const n = @as([*]const u8, @ptrCast(needle));

    var found: ?[*]const u8 = null;

    if (needle_len >= 4 and needle_len <= AC_MAX_PATTERN) {
        var ac: ac_lite_t = undefined;
        ac_lite_build(&ac, n, needle_len);
        found = ac_lite_search_neon(&ac, haystack, hlen);
    }

    if (found == null) {
        found = simd_memmem_neon(haystack, hlen, n, needle_len);
    }

    c.caml_leave_blocking_section();

    const ret: c_int = if (found != null) 1 else 0;

    _ = c.munmap(addr, @intCast(st.st_size));
    _ = c.close(fd);

    return Val_int(ret);
}
