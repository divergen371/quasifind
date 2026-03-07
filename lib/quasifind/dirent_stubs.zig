const std = @import("std");
const c = @cImport({
    @cInclude("sys/types.h");
    @cInclude("dirent.h");
    @cInclude("string.h");
    @cInclude("errno.h");
    @cInclude("caml/mlvalues.h");
    @cInclude("caml/memory.h");
    @cInclude("caml/alloc.h");
    @cInclude("caml/fail.h");
    @cInclude("caml/unixsupport.h");
    @cInclude("caml/custom.h");
});

// Explicitly use extern struct to guarantee C ABI compatibility
const dir_handle_t = extern struct {
    dir: ?*c.DIR,
    pending_name: [256]u8,
    pending_kind: c_int,
    has_pending: c_int,
};

fn map_dtype(d_type: u8) c_int {
    return switch (d_type) {
        c.DT_REG => 1,
        c.DT_DIR => 2,
        c.DT_LNK => 3,
        else => 0,
    };
}

inline fn String_val(v: c.value) [*c]const u8 {
    return @as([*c]const u8, @ptrFromInt(@as(usize, @bitCast(v))));
}

inline fn Bytes_val(v: c.value) [*c]u8 {
    return @as([*c]u8, @ptrFromInt(@as(usize, @bitCast(v))));
}

inline fn Int_val(v: c.value) c_int {
    return @as(c_int, @intCast(@as(isize, @bitCast(v)) >> 1));
}

inline fn Val_int(i: c_int) c.value {
    return @as(c.value, @bitCast((@as(isize, i) << 1) | 1));
}

inline fn set_errno(val: c_int) void {
    if (@hasDecl(c, "__error")) {
        c.__error().* = val;
    } else if (@hasDecl(c, "__errno_location")) {
        c.__errno_location().* = val;
    }
}

inline fn get_errno() c_int {
    if (@hasDecl(c, "__error")) {
        return c.__error().*;
    } else if (@hasDecl(c, "__errno_location")) {
        return c.__errno_location().*;
    }
    return 0;
}

// Helper to access custom block data safely
inline fn customVal(v: c.value) *dir_handle_t {
    if (@hasDecl(c, "Data_custom_val")) {
        return @as(*dir_handle_t, @ptrCast(@alignCast(c.Data_custom_val(v))));
    } else {
        const ptr = @as([*c]c.value, @ptrFromInt(v));
        return @as(*dir_handle_t, @ptrCast(@alignCast(&ptr[1])));
    }
}

export fn finalize_dir_handle(v_dir: c.value) void {
    const dh = customVal(v_dir);
    if (dh.dir) |d| {
        _ = c.closedir(d);
        dh.dir = null;
    }
}

var dir_handle_ops = c.custom_operations{
    .identifier = "quasifind.dir_handle",
    .finalize = finalize_dir_handle,
    .compare = @ptrCast(@alignCast(c.custom_compare_default)),
    .hash = @ptrCast(@alignCast(c.custom_hash_default)),
    .serialize = @ptrCast(@alignCast(c.custom_serialize_default)),
    .deserialize = @ptrCast(@alignCast(c.custom_deserialize_default)),
    .compare_ext = @ptrCast(@alignCast(c.custom_compare_ext_default)),
    .fixed_length = @ptrCast(@alignCast(c.custom_fixed_length_default)),
};

export fn caml_opendir(v_path: c.value) c.value {
    const path = String_val(v_path);
    const d = c.opendir(path);
    if (d == null) {
        c.uerror("opendir", v_path);
        unreachable;
    }

    // Allocate the custom block via OCaml GC
    const v_dir = c.caml_alloc_custom(&dir_handle_ops, @sizeOf(dir_handle_t), 0, 1);

    // Initialize the fields explicitly
    const dh = customVal(v_dir);
    dh.dir = d;
    dh.has_pending = 0;

    return v_dir;
}

export fn caml_closedir(v_dir: c.value) c.value {
    const dh = customVal(v_dir);
    if (dh.dir) |d| {
        _ = c.closedir(d);
        dh.dir = null;
    }
    return c.Val_unit;
}

// OCaml array access helpers
//
// NOTE: We cannot use the official Wosize_val / Hd_val macros from caml/mlvalues.h
// because they contain volatile pointer casts that Zig's @cImport translates into
// extern function calls (e.g. _Hd_val), which are not actual symbols in the OCaml
// runtime and cause linker errors ("Undefined symbols: _Hd_val").
//
// Instead, we manually read the OCaml block header. The layout is:
//   [wosize (54 bits on 64-bit) | color (2 bits) | tag (8 bits)]
//   i.e. wosize = header >> 10
//
// This is stable across OCaml 4.x and 5.x on 64-bit platforms.
// Reference: https://v2.ocaml.org/api/compilerlibref/Obj.html
//            runtime/caml/mlvalues.h  (HEADER_WOSIZE_SHIFT = 10)
// If OCaml changes this layout in a future major version, this MUST be updated.
inline fn OCaml_Array_length(v: c.value) c_int {
    const ptr = @as([*c]c.value, @ptrFromInt(@as(usize, @bitCast(v))));
    const header = (ptr - 1)[0];
    return @intCast(header >> 10);
}

inline fn OCaml_Array_get(v: c.value, i: c_int) c.value {
    const ptr = @as([*c]c.value, @ptrFromInt(@as(usize, @bitCast(v))));
    return ptr[@as(usize, @intCast(i))];
}

// Function to parse OCaml string array into a Zig slice of C strings
fn parse_string_array(ocaml_array: c.value, allocator: std.mem.Allocator) ![][*c]const u8 {
    const len = OCaml_Array_length(ocaml_array);
    var list = try allocator.alloc([*c]const u8, @intCast(len));
    for (0..@intCast(len)) |i| {
        const ocaml_string = OCaml_Array_get(ocaml_array, @intCast(i));
        list[i] = String_val(ocaml_string);
    }
    return list;
}

// Checks if a string matches any prefix in the list
fn matches_prefix(name: [*c]const u8, prefixes: [][*c]const u8) bool {
    if (prefixes.len == 0) return true;
    for (prefixes) |prefix| {
        if (c.strncmp(name, prefix, c.strlen(prefix)) == 0) {
            return true;
        }
    }
    return false;
}

// Checks if a string matches any suffix in the list
fn matches_suffix(name: [*c]const u8, suffixes: [][*c]const u8) bool {
    if (suffixes.len == 0) return true;
    const name_len = c.strlen(name);
    for (suffixes) |suffix| {
        const suffix_len = c.strlen(suffix);
        if (name_len >= suffix_len) {
            if (c.strcmp(name + (name_len - suffix_len), suffix) == 0) {
                return true;
            }
        }
    }
    return false;
}

export fn caml_readdir_batch(v_dir: c.value, v_prefixes: c.value, v_suffixes: c.value) c.value {
    const dh = customVal(v_dir);
    if (dh.dir == null) {
        c.caml_failwith("Directory already closed");
        unreachable;
    }

    // FixedBufferAllocator is incredibly fast and avoids system allocator overhead
    var temp_buf: [32768]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&temp_buf);
    const allocator = fba.allocator();

    const prefixes = parse_string_array(v_prefixes, allocator) catch {
        c.caml_failwith("Failed to parse prefix arrays");
        unreachable;
    };
    const suffixes = parse_string_array(v_suffixes, allocator) catch {
        c.caml_failwith("Failed to parse suffix arrays");
        unreachable;
    };

    // Batch sizing policy
    //
    // BATCH_MAX: Maximum number of *filter-passing* entries returned per call.
    //   Smaller batches yield control to OCaml (and its GC) more frequently,
    //   but increase FFI call overhead.  1000 is a sweet spot that keeps each
    //   batch under ~40 KB of OCaml heap and typically completes in < 1 ms.
    //
    // SCAN_MAX: Maximum number of *raw* readdir() calls per batch, regardless
    //   of how many entries pass the prefix/suffix filter.  Without this cap,
    //   a highly sparse directory (e.g. 1M entries, only 2 .jpg files) would
    //   block the OCaml GC for the entire duration of a single batch call.
    //   When SCAN_MAX is reached we return the partial batch; the caller loops.
    const BATCH_MAX: usize = 1000;
    const SCAN_MAX: usize = 4000; // never read more than 4× the batch size raw

    var results_arr: [BATCH_MAX]struct { name: [*c]const u8, kind: c_int } = undefined;

    var count: usize = 0; // entries that passed the filter
    var scanned: usize = 0; // total readdir() calls this batch

    // Release OCaml lock for the entire batch scanning process.
    // This removes the massive overhead of toggling the domain lock
    // on every single raw readdir() call.
    c.caml_enter_blocking_section();

    while (count < BATCH_MAX and scanned < SCAN_MAX) {
        set_errno(0);
        const entry = c.readdir(dh.dir);
        scanned += 1;

        if (entry == null) {
            if (get_errno() != 0) {
                // If readdir failed, we must re-acquire lock before raising exceptions
                c.caml_leave_blocking_section();
                c.uerror("readdir", c.Nothing);
                unreachable;
            }
            break; // EOF
        }

        const e = entry.?;
        const d_name = @as([*c]const u8, @ptrCast(&e.*.d_name));

        // Ignore . and .. inside C to save FFI trips
        if (c.strcmp(d_name, ".") == 0 or c.strcmp(d_name, "..") == 0) continue;

        // Perform AST Push-Down optimizations (Zero-allocation filtering)
        if (!matches_prefix(d_name, prefixes)) continue;
        if (!matches_suffix(d_name, suffixes)) continue;

        // Passed filter
        const kind: c_int = switch (e.*.d_type) {
            c.DT_REG => 1,
            c.DT_DIR => 2,
            c.DT_LNK => 3,
            c.DT_UNKNOWN => 0,
            else => 4,
        };

        // strdup is safe to call without OCaml lock because it uses libc malloc
        const dup_name = c.strdup(d_name);
        if (dup_name == null) {
            // Free already allocated strings and fail
            for (results_arr[0..count]) |res| {
                c.free(@as(?*anyopaque, @ptrCast(@constCast(res.name))));
            }
            c.caml_leave_blocking_section();
            c.caml_failwith("strdup failed in readdir_batch");
            unreachable;
        }
        results_arr[count] = .{ .name = dup_name, .kind = kind };
        count += 1;
    }

    // Re-acquire OCaml lock before allocating OCaml values
    c.caml_leave_blocking_section();

    if (count == 0) {
        return c.Atom(0); // empty array in OCaml is Atom(0)
    }

    const ocaml_arr_orig = c.caml_alloc(@intCast(count), 0); // Tag 0 for Array
    var ocaml_arr: c.value = ocaml_arr_orig;
    c.caml_register_global_root(&ocaml_arr);

    const results = results_arr[0..count];

    for (results, 0..) |res, i| {
        const str_val_orig = c.caml_copy_string(res.name);
        var str_val: c.value = str_val_orig;
        c.free(@as(?*anyopaque, @ptrCast(@constCast(res.name)))); // Free the strdup'd string

        c.caml_register_global_root(&str_val);
        const tuple = c.caml_alloc(2, 0);
        c.caml_remove_global_root(&str_val);

        const p_tuple = @as([*c]c.value, @ptrFromInt(@as(usize, @bitCast(tuple))));
        p_tuple[0] = str_val;
        p_tuple[1] = Val_int(res.kind);

        const p_arr = @as([*c]c.value, @ptrFromInt(@as(usize, @bitCast(ocaml_arr))));
        p_arr[i] = tuple;
    }

    c.caml_remove_global_root(&ocaml_arr);
    return ocaml_arr;
}
