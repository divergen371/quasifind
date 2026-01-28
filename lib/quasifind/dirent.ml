type kind =
  | Unknown
  | Reg
  | Dir
  | Symlink
  | Other

external readdir_internal : string -> (string * int) list = "caml_readdir_with_type"

let readdir path =
  let entries = readdir_internal path in
  List.map (fun (name, k) ->
    let kind = match k with
      | 1 -> Reg
      | 2 -> Dir
      | 3 -> Symlink
      | 4 -> Other
      | _ -> Unknown
    in
    (name, kind)
  ) entries

type dir_handle

external opendir : string -> dir_handle = "caml_opendir"
external closedir : dir_handle -> unit = "caml_closedir"
external readdir_batch_c : dir_handle -> bytes -> int -> int -> int = "caml_readdir_batch"

(* Iterator for batch entries *)
let iter_batch (path : string) (f : string -> kind -> unit) =
  let buf_size = 8192 in (* 8KB buffer *)
  let buf = Bytes.create buf_size in
  let dir = opendir path in
  
  try
    let rec loop () =
      let written = readdir_batch_c dir buf 0 buf_size in
      if written > 0 then (
        let ptr = ref 0 in
        while !ptr < written do
          let p = !ptr in
          let k_int = Char.code (Bytes.get buf p) in
          let kind = match k_int with
             | 1 -> Reg
             | 2 -> Dir
             | 3 -> Symlink
             | 4 -> Other
             | _ -> Unknown
          in
          let len_low = Char.code (Bytes.get buf (p + 1)) in
          let len_high = Char.code (Bytes.get buf (p + 2)) in
          let len = len_low lor (len_high lsl 8) in
          let name = Bytes.sub_string buf (p + 3) len in
          
          f name kind;
          
          ptr := p + 3 + len
        done;
        loop ()
      )
    in
    loop ();
    closedir dir
  with exn ->
    closedir dir;
    raise exn
