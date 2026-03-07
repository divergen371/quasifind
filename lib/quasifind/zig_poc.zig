// PoC: OCaml → Zig FFI bridge verification
// This function returns an OCaml string "Hello from Zig!" to the OCaml caller.
//
// OCaml C FFI rules:
//  - Functions take OCaml `value` args (= `usize` on 64-bit).
//  - Call CAMLparam/CAMLreturn macros via the raw caml headers (imported as C).
//  - `caml_copy_string` returns an allocated OCaml string value.

const std = @import("std");
const c = @cImport({
    @cInclude("caml/alloc.h");
    @cInclude("caml/mlvalues.h");
});

/// `external zig_dummy_hello : unit -> string = "zig_dummy_hello"`
export fn zig_dummy_hello(unit: c.value) c.value {
    _ = unit;
    return c.caml_copy_string("Hello from Zig!");
}
