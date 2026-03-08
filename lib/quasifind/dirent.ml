type kind =
  | Unknown
  | Reg
  | Dir
  | Symlink
  | Other

type dir_handle

external opendir : string -> dir_handle = "caml_opendir"
external closedir : dir_handle -> unit = "caml_closedir"

(* Batch reading interface with built-in prefix/suffix filtering *)
external readdir_batch : dir_handle -> string array -> string array -> bool -> (string * kind * int * int) array = "caml_readdir_batch"

(* Iterator for batch entries *)
let iter_batch ?(prefixes=[||]) ?(suffixes=[||]) ~needs_stat (path : string) (f : string -> kind -> int -> int -> unit) =
  let h = opendir path in
  let rec loop () =
    let batch = readdir_batch h prefixes suffixes needs_stat in
    let len = Array.length batch in
    if len > 0 then begin
      for i = 0 to len - 1 do
        let (name, kind, size, mtime) = Array.unsafe_get batch i in
        f name kind size mtime
      done;
      loop ()
    end else begin
      closedir h
    end
  in
  try loop ()
  with exn ->
    closedir h;
    raise exn

let readdir path =
  let acc = ref [] in
  iter_batch ~needs_stat:true path (fun name kind size mtime ->
    acc := (name, kind, size, mtime) :: !acc
  );
  List.rev !acc
