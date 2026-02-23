open Ast
open Ast.Typed

type entry = {
  name : string;
  path : string;
  kind : Ast.file_type;
  size : int64;
  mtime : float; (* absolute usage time *)
  perm : int;
}

(* Helper functions defined in correct order *)

let check_string op s =
  match op with
  | StrEq target -> String.equal s target
  | StrNe target -> not (String.equal s target)
  | StrRe (_, re) -> Re.execp re s

(* Helper to wrap operations with timestamp preservation *)
let with_timestamp_preservation path preserve f =
  if preserve then
    match Unix.lstat path with
    | stats ->
        let atime = stats.st_atime in
        let mtime = stats.st_mtime in
        let res = f () in
        (try 
           Unix.utimes path atime mtime;
         with _ -> ());
        res
    | exception _ -> f ()
  else
    f ()

module BufferPool = struct
  let pool = Saturn.Queue.create ()
  
  let acquire min_size =
    let rec try_pop () =
      match Saturn.Queue.pop_opt pool with
      | Some b when Bytes.length b >= min_size -> b
      | Some _ -> try_pop () (* Discard too small buffers *)
      | None -> Bytes.create min_size
    in try_pop ()

  let release b =
    (* Don't pool excessively large buffers (>16MB) to avoid memory bloat *)
    if Bytes.length b <= 16 * 1024 * 1024 then
      Saturn.Queue.push pool b
end

(* Helper to read file content into a pooled buffer and run a function on it *)
let with_file_content path preserve f =
  let read () =
    try
      let ic = open_in_bin path in
      let len = in_channel_length ic in
      if len = 0 then begin
        close_in ic;
        f (Some "")
      end else begin
        let buf = BufferPool.acquire len in
        let _read_len = really_input ic buf 0 len in
        close_in ic;
        (* Unsafe conversion is fine because we own the buffer exclusively
           during the callback `f`, and we only read from the string. *)

        (* We must pass only the valid substring if the buffer is larger,
           but wait, Bytes.sub creates a copy! 
           Actually, unsafe_to_string makes the WHOLE buffer a string.
           Wait, there is no String.sub without allocation.
           But we know the buffer is at least `len`. We should just allocate EXACTLY `len`?
           No! We can just pass a string slice, but OCaml strings don't have slices.
           Wait, `Re.execp` handles standard strings. If the string is larger,
           it will search the garbage at the end! 
           To avoid this, we can use `Bytes.sub_string` which DOES allocate, defeating the purpose. 
           But if we just allocate a buffer of *exactly* len when it's not the right size? 
           Still better to reuse if sizes are similar? 
           Actually, OCaml 5 has `String.sub` which allocates.
           Is there a way to avoid allocation? `Bytes.unsafe_to_string` works if `Bytes.length buf == len`.
           If we only pool exact sizes? That's unlikely to hit.
           Let's just use `really_input_string ic len` for now if we can't safely slice.
           Wait! `in_channel_length` returns the length of the file.
           The pooling approach is useful if we use `Bytes.t` for calculation.
           Let's leave `read_file_content` as is for now and focus pooling on where we can control it. *)
        let s = Bytes.sub_string buf 0 len in
        BufferPool.release buf;
        f (Some s)
      end
    with _ -> f None
  in
  with_timestamp_preservation path preserve read

let check_content path preserve op =
  match op with
  (* Fast path: literal string search via mmap+memmem (SIMD-optimized) *)
  | StrEq target ->
      with_timestamp_preservation path preserve (fun () ->
        match Search.memmem path target with
        | Search.Match -> true
        | Search.NoMatch -> false
        | Search.Fallback ->
            (* Fallback to read+compare *)
            with_file_content path false (function
            | Some content -> String.equal content target
            | None -> false))
  | StrNe target ->
      with_timestamp_preservation path preserve (fun () ->
        match Search.memmem path target with
        | Search.Match -> false
        | Search.NoMatch -> true
        | Search.Fallback ->
            with_file_content path false (function
            | Some content -> not (String.equal content target)
            | None -> true))
  (* Fast path: Try mmap+regex if possible *)
  | StrRe (pattern, re) ->
      with_timestamp_preservation path preserve (fun () ->
        match Search.regex path pattern with
        | Search.Match -> true
        | Search.NoMatch -> false
        | Search.Fallback -> 
            with_file_content path false (function
             | Some content -> Re.execp re content
             | None -> false))


let calculate_entropy content =
  let len = String.length content in
  if len = 0 then 0.0
  else
    let counts = Array.make 256 0 in
    String.iter (fun c ->
      let code = Char.code c in
      counts.(code) <- counts.(code) + 1
    ) content;
    let total = float_of_int len in
    let entropy = ref 0.0 in
    Array.iter (fun count ->
      if count > 0 then
        let p = float_of_int count /. total in
        entropy := !entropy -. (p *. log p /. log 2.0)
    ) counts;
    !entropy

let check_float op f =
  match op with
  | FloatEq target -> Float.abs (f -. target) < epsilon_float
  | FloatNe target -> Float.abs (f -. target) >= epsilon_float
  | FloatLt target -> f < target
  | FloatLe target -> f <= target
  | FloatGt target -> f > target
  | FloatGe target -> f >= target

let check_entropy path preserve op =
  with_file_content path preserve (function
  | Some content -> check_float op (calculate_entropy content)
  | None -> false)

let check_type op t =
  match op with
  | TypeEq target -> equal_file_type t target
  | TypeNe target -> not (equal_file_type t target)

let check_size op s =
  match op with
  | SizeEq target -> s = target
  | SizeNe target -> s <> target
  | SizeLt target -> s < target
  | SizeLe target -> s <= target
  | SizeGt target -> s > target
  | SizeGe target -> s >= target

let check_time now op mtime =
  let age = now -. mtime in
  match op with
  | TimeEq target -> age = target
  | TimeNe target -> age <> target
  | TimeLt target -> age < target
  | TimeLe target -> age <= target
  | TimeGt target -> age > target
  | TimeGe target -> age >= target

let check_perm op perm =
  match op with
  | PermEq target -> perm = target
  | PermNe target -> perm <> target
  | PermLt target -> perm < target
  | PermLe target -> perm <= target
  | PermGt target -> perm > target
  | PermGe target -> perm >= target

(* Constant folding optimization *)
let rec optimize (expr : Typed.expr) : Typed.expr =
  match expr with
  | Not True -> False
  | Not False -> True
  | Not e -> 
      (match optimize e with 
       | True -> False 
       | False -> True 
       | e' -> Not e')
  | And (e1, e2) ->
      (match optimize e1, optimize e2 with
       | False, _ | _, False -> False
       | True, e | e, True -> e
       | e1', e2' -> And (e1', e2'))
  | Or (e1, e2) ->
      (match optimize e1, optimize e2 with
       | True, _ | _, True -> True
       | False, e | e, False -> e
       | e1', e2' -> Or (e1', e2'))
  | _ -> expr

(* Main eval function with optional timestamp preservation *)
let rec eval ?(preserve_timestamps=false) (now : float) (expr : Typed.expr) (ent : entry) : bool =
  let recurse = eval ~preserve_timestamps now in
  match expr with
  | True -> true
  | False -> false
  | Not e -> not (recurse e ent)
  | And (e1, e2) -> (recurse e1 ent) && (recurse e2 ent)
  | Or (e1, e2) -> (recurse e1 ent) || (recurse e2 ent)
  | Name op -> check_string op ent.name
  | Path op -> check_string op ent.path
  | Content op -> check_content ent.path preserve_timestamps op
  | Type op -> check_type op ent.kind
  | Size op -> check_size op ent.size
  | MTime op -> check_time now op ent.mtime
  | Perm op -> check_perm op ent.perm
  | Entropy op -> check_entropy ent.path preserve_timestamps op

(* Analyze expression to check if it depends on metadata (stat) *)
let rec requires_metadata (expr : Typed.expr) : bool =
  match expr with
  | True | False -> false
  | Not e -> requires_metadata e
  | And (e1, e2) | Or (e1, e2) -> requires_metadata e1 || requires_metadata e2
  | Name _ | Path _ | Content _ | Entropy _ | Type _ -> false (* Type is handled via Dirent.kind, Content/Entropy read file directly but don't strictly need stat for filtering if logic separates them *)
  | Size _ | MTime _ | Perm _ -> true

(* Path pruning analysis: Check if a directory path can be pruned.
   Returns true if we can definitively skip this directory and all its children.
   Conservative: only prunes when we're absolutely sure nothing below can match. *)
let rec can_prune_path (dir_path : string) (expr : Typed.expr) : bool =
  match expr with
  | True -> false  (* Can't prune - everything matches *)
  | False -> true  (* Can prune - nothing matches *)
  | Not e -> 
      (* Can't easily prune negations - be conservative *)
      if can_prune_path dir_path e then false else false
  | And (e1, e2) -> 
      (* If either branch says prune, we can prune *)
      can_prune_path dir_path e1 || can_prune_path dir_path e2
  | Or (e1, e2) -> 
      (* Both branches must agree to prune *)
      can_prune_path dir_path e1 && can_prune_path dir_path e2
  | Path (StrEq target) ->
      (* Path must equal target - prune if dir_path is not a prefix of target *)
      let target_norm = if String.length target > 0 && target.[0] = '.' then target else "./" ^ target in
      let dir_norm = if String.length dir_path > 0 && dir_path.[0] = '.' then dir_path else "./" ^ dir_path in
      not (String.starts_with ~prefix:dir_norm target_norm || String.starts_with ~prefix:target_norm dir_norm)
  | Path (StrRe (pattern, _)) ->
      (* Check if pattern has a literal prefix we can use *)
      (* Extract prefix before any regex metacharacter *)
      let rec find_prefix i =
        if i >= String.length pattern then pattern
        else match pattern.[i] with
        | '.' | '*' | '+' | '?' | '[' | '(' | '{' | '|' | '^' | '$' | '\\' -> String.sub pattern 0 i
        | _ -> find_prefix (i + 1)
      in
      let prefix = find_prefix 0 in
      if String.length prefix > 2 then
        let dir_norm = if String.length dir_path > 0 && dir_path.[0] = '.' then dir_path else "./" ^ dir_path in
        not (String.starts_with ~prefix:dir_norm prefix || String.starts_with ~prefix dir_norm)
      else
        false (* Prefix too short, can't prune safely *)
  | Name _ | Path (StrNe _) | Content _ | Entropy _ | Type _ | Size _ | MTime _ | Perm _ ->
      false (* These don't constrain path prefix, can't prune *)
