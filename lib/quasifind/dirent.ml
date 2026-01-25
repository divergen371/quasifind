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
