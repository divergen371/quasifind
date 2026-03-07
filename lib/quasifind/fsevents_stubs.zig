const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    if (builtin.os.tag == .macos) {
        @cInclude("pthread.h");
        @cInclude("string.h");
        @cInclude("stdlib.h");
    }
    @cInclude("caml/mlvalues.h");
    @cInclude("caml/memory.h");
    @cInclude("caml/alloc.h");
    @cInclude("caml/fail.h");
    @cInclude("caml/callback.h");
});

// Manual macOS CoreServices bindings to bypass massive header parse errors in @cImport
const CFStringRef = ?*anyopaque;
const CFArrayRef = ?*anyopaque;
const FSEventStreamRef = ?*anyopaque;
const CFAllocatorRef = ?*anyopaque;
const dispatch_queue_t = ?*anyopaque;

const kCFStringEncodingUTF8: u32 = 0x08000100;
const kFSEventStreamEventIdSinceNow: u64 = 0xFFFFFFFFFFFFFFFF;
const kFSEventStreamCreateFlagNoDefer: u32 = 0x00000002;
const kFSEventStreamCreateFlagFileEvents: u32 = 0x00000010;
const DISPATCH_QUEUE_PRIORITY_DEFAULT: isize = 0;

extern "c" const kCFTypeArrayCallBacks: anyopaque;

extern "c" fn CFStringCreateWithCString(alloc: CFAllocatorRef, cStr: [*c]const u8, encoding: u32) CFStringRef;
extern "c" fn CFArrayCreate(alloc: CFAllocatorRef, values: [*c]const ?*anyopaque, numValues: isize, callBacks: ?*const anyopaque) CFArrayRef;
extern "c" fn CFRelease(cf: ?*anyopaque) void;

extern "c" fn FSEventStreamCreate(
    alloc: CFAllocatorRef,
    callback: ?*const anyopaque,
    context: ?*anyopaque,
    pathsToWatch: CFArrayRef,
    sinceWhen: u64,
    latency: f64,
    flags: u32,
) FSEventStreamRef;

extern "c" fn FSEventStreamSetDispatchQueue(streamRef: FSEventStreamRef, q: dispatch_queue_t) void;
extern "c" fn FSEventStreamStart(streamRef: FSEventStreamRef) u8;
extern "c" fn FSEventStreamStop(streamRef: FSEventStreamRef) void;
extern "c" fn FSEventStreamInvalidate(streamRef: FSEventStreamRef) void;
extern "c" fn FSEventStreamRelease(streamRef: FSEventStreamRef) void;

extern "c" fn dispatch_get_global_queue(identifier: isize, flags: usize) dispatch_queue_t;
extern "c" fn usleep(microseconds: u32) c_int;

inline fn String_val(v: c.value) [*c]const u8 {
    return @as([*c]const u8, @ptrFromInt(@as(usize, @bitCast(v))));
}

inline fn Double_val(v: c.value) f64 {
    // OCaml's Double_val(v) is defined as ((double *)(v))[0].
    // The OCaml value `v` points directly to the double payload (past the header).
    //
    // On most 64-bit platforms (x86_64, aarch64), word alignment == double alignment,
    // so a direct pointer cast and dereference is safe.
    //
    // However, on platforms where ARCH_ALIGN_DOUBLE is defined (e.g. some 32-bit ARM),
    // doubles may require stricter alignment than word alignment. OCaml handles this
    // internally via union-based reconstruction from two 32-bit words.
    //
    // For maximum portability, we use @memcpy into a stack-local f64, which Zig
    // guarantees to be properly aligned. This avoids any potential unaligned access
    // regardless of the target platform, with zero overhead on aligned platforms
    // (the compiler will optimize this to a single load).
    const src = @as([*]const u8, @ptrFromInt(@as(usize, @bitCast(v))));
    var result: f64 = undefined;
    @memcpy(std.mem.asBytes(&result), src[0..@sizeOf(f64)]);
    return result;
}

inline fn Val_int(i: c_int) c.value {
    return @as(c.value, @bitCast((@as(isize, i) << 1) | 1));
}

inline fn Int_val(v: c.value) c_int {
    return @as(c_int, @intCast(@as(isize, @bitCast(v)) >> 1));
}

const MAX_EVENTS: usize = 4096;
const MAX_PATH_LEN: usize = 1024;

const EventBuf = struct {
    paths: [MAX_EVENTS][MAX_PATH_LEN]u8,
    head: usize,
    tail: usize,
    count: usize,
    mutex: c.pthread_mutex_t,
};

var event_buf: EventBuf = undefined;
var stream: FSEventStreamRef = null;
var watch_thread: c.pthread_t = undefined;
var running = std.atomic.Value(bool).init(false);

fn init_fsevents() void {
    if (builtin.os.tag == .macos) {
        event_buf.head = 0;
        event_buf.tail = 0;
        event_buf.count = 0;

        // PTHREAD_MUTEX_INITIALIZER is tricky in Zig. We init dynamically.
        _ = c.pthread_mutex_init(&event_buf.mutex, null);
    }
}

fn push_event(path: [*c]const u8) void {
    if (builtin.os.tag != .macos) return;

    _ = c.pthread_mutex_lock(&event_buf.mutex);
    if (event_buf.count < MAX_EVENTS) {
        const p_len = c.strlen(path);
        const copy_len = @min(p_len, MAX_PATH_LEN - 1);
        @memcpy(event_buf.paths[event_buf.tail][0..copy_len], path[0..copy_len]);
        event_buf.paths[event_buf.tail][copy_len] = 0;
        event_buf.tail = (event_buf.tail + 1) % MAX_EVENTS;
        event_buf.count += 1;
    }
    _ = c.pthread_mutex_unlock(&event_buf.mutex);
}

export fn fsevents_callback(
    streamRef: ?*anyopaque,
    clientCallBackInfo: ?*anyopaque,
    numEvents: usize,
    eventPaths: ?*anyopaque,
    eventFlags: ?*anyopaque,
    eventIds: ?*anyopaque,
) void {
    _ = streamRef;
    _ = clientCallBackInfo;
    _ = eventFlags;
    _ = eventIds;

    const paths = @as([*c][*c]u8, @ptrCast(@alignCast(eventPaths)));
    var i: usize = 0;
    while (i < numEvents) : (i += 1) {
        push_event(paths[i]);
    }
}

export fn runloop_thread(arg: ?*anyopaque) ?*anyopaque {
    _ = arg;
    if (builtin.os.tag == .macos) {
        const queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        FSEventStreamSetDispatchQueue(stream, queue);
        _ = FSEventStreamStart(stream);

        while (running.load(.seq_cst)) {
            _ = usleep(100000);
        }
    }
    return null;
}

export fn caml_fsevents_start(v_path: c.value, v_latency: c.value) c.value {
    if (builtin.os.tag != .macos) {
        return Val_int(-1);
    }

    if (running.load(.seq_cst)) {
        return Val_int(0);
    }

    // Init state if running for the first time
    if (stream == null) {
        init_fsevents();
    }

    const path = String_val(v_path);
    const latency = Double_val(v_latency);

    const cf_path = CFStringCreateWithCString(null, path, kCFStringEncodingUTF8);
    var cf_path_arr: [1]?*anyopaque = undefined;
    cf_path_arr[0] = cf_path;
    const paths_to_watch = CFArrayCreate(null, @ptrCast(&cf_path_arr[0]), 1, &kCFTypeArrayCallBacks);

    stream = FSEventStreamCreate(
        null,
        @ptrCast(&fsevents_callback),
        null,
        paths_to_watch,
        kFSEventStreamEventIdSinceNow,
        latency,
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer,
    );

    CFRelease(cf_path);
    CFRelease(paths_to_watch);

    if (stream == null) {
        return Val_int(-1);
    }

    running.store(true, .seq_cst);
    if (c.pthread_create(&watch_thread, null, runloop_thread, null) != 0) {
        running.store(false, .seq_cst);
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        stream = null;
        return Val_int(-1);
    }

    return Val_int(1);
}

export fn caml_fsevents_poll(v_unit: c.value) c.value {
    _ = v_unit;
    if (builtin.os.tag != .macos) {
        return c.Val_emptylist;
    }

    var count: usize = 0;
    var snapshot: ?[*c][*c]u8 = null;

    _ = c.pthread_mutex_lock(&event_buf.mutex);
    count = event_buf.count;
    if (count > 0) {
        snapshot = @as([*c][*c]u8, @ptrCast(@alignCast(c.malloc(count * @sizeOf([*c]u8)))));
        if (snapshot != null) {
            const snap = snapshot.?;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                snap[i] = c.strdup(@ptrCast(&event_buf.paths[event_buf.head]));
                if (snap[i] == null) {
                    const msg = "[Warning] strdup failed in fsevents_poll: event dropped\n";
                    _ = std.posix.write(std.posix.STDERR_FILENO, msg) catch {};
                }
                event_buf.head = (event_buf.head + 1) % MAX_EVENTS;
            }
            event_buf.count = 0;
        } else {
            const msg = "[Warning] malloc failed in fsevents_poll: events dropped\n";
            _ = std.posix.write(std.posix.STDERR_FILENO, msg) catch {};
            count = 0;
        }
    }
    _ = c.pthread_mutex_unlock(&event_buf.mutex);

    var result = c.Val_emptylist;

    if (snapshot) |snap| {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (snap[i] != null) {
                // To avoid macro issues we manually create cons cell: Block of size 2, tag 0.
                const cons = c.caml_alloc(2, 0);

                // Store_field equivalent:
                // caml_modify(&Field(cons, 0), caml_copy_string(snap[i]))
                // But caml_alloc returns uninitialized, so direct assignment is fine like in C stubs.
                // We use caml_modify for safety or just pointer arithmetic.
                const p_cons = @as([*c]c.value, @ptrFromInt(@as(usize, @bitCast(cons))));

                p_cons[0] = c.caml_copy_string(snap[i]);
                p_cons[1] = result;

                result = cons;
                c.free(snap[i]);
            }
        }
        c.free(@ptrCast(snap));
    }

    return result;
}

export fn caml_fsevents_stop(v_unit: c.value) c.value {
    _ = v_unit;
    if (builtin.os.tag == .macos) {
        if (running.load(.seq_cst) and stream != null) {
            running.store(false, .seq_cst);
            FSEventStreamStop(stream);
            FSEventStreamInvalidate(stream);
            FSEventStreamRelease(stream);
            stream = null;
            _ = c.pthread_join(watch_thread, null);
        }
    }
    return c.Val_unit;
}
