open Eio.Std

type request =
  | Query of Ast.Typed.expr
  | Stats
  | Shutdown

type response = 
  | Success of Yojson.Safe.t
  | Failure of string

let socket_path () =
  let xdg_runtime = try Sys.getenv "XDG_RUNTIME_DIR" with Not_found -> 
    let home = try Sys.getenv "HOME" with Not_found -> "/tmp" in
    Filename.concat home ".cache"
  in
  let dir = Filename.concat xdg_runtime "quasifind" in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o700;
  Filename.concat dir "daemon.sock"

(* JSON Serialization for AST *)
let rec expr_to_json (e : Ast.Typed.expr) : Yojson.Safe.t =
  let open Ast.Typed in
  match e with
  | True -> `Assoc [("op", `String "true")]
  | False -> `Assoc [("op", `String "false")]
  | Not e -> `Assoc [("op", `String "not"); ("ptr", expr_to_json e)]
  | And (e1, e2) -> `Assoc [("op", `String "and"); ("left", expr_to_json e1); ("right", expr_to_json e2)]
  | Or (e1, e2) -> `Assoc [("op", `String "or"); ("left", expr_to_json e1); ("right", expr_to_json e2)]
  (* String Ops *)
  | Name (StrEq s) -> `Assoc [("op", `String "name_eq"); ("val", `String s)]
  | Name (StrNe s) -> `Assoc [("op", `String "name_ne"); ("val", `String s)]
  | Name (StrRe (s, _)) -> `Assoc [("op", `String "name_re"); ("val", `String s)] 
  | Path (StrEq s) -> `Assoc [("op", `String "path_eq"); ("val", `String s)]
  | Path (StrNe s) -> `Assoc [("op", `String "path_ne"); ("val", `String s)]
  | Path (StrRe (s, _)) -> `Assoc [("op", `String "path_re"); ("val", `String s)]
  | Content (StrEq s) -> `Assoc [("op", `String "content_eq"); ("val", `String s)]
  | Content (StrNe s) -> `Assoc [("op", `String "content_ne"); ("val", `String s)]
  | Content (StrRe (s, _)) -> `Assoc [("op", `String "content_re"); ("val", `String s)]
  (* Type Ops *)
  | Type (TypeEq t) -> 
      let s = match t with File -> "f" | Dir -> "d" | Symlink -> "l" in
      `Assoc [("op", `String "type_eq"); ("val", `String s)]
  | Type (TypeNe t) ->
      let s = match t with File -> "f" | Dir -> "d" | Symlink -> "l" in
      `Assoc [("op", `String "type_ne"); ("val", `String s)]
  (* Size Ops *)
  | Size (SizeEq n) -> `Assoc [("op", `String "size_eq"); ("val", `Intlit (Int64.to_string n))]
  | Size (SizeNe n) -> `Assoc [("op", `String "size_ne"); ("val", `Intlit (Int64.to_string n))]
  | Size (SizeLt n) -> `Assoc [("op", `String "size_lt"); ("val", `Intlit (Int64.to_string n))]
  | Size (SizeLe n) -> `Assoc [("op", `String "size_le"); ("val", `Intlit (Int64.to_string n))]
  | Size (SizeGt n) -> `Assoc [("op", `String "size_gt"); ("val", `Intlit (Int64.to_string n))]
  | Size (SizeGe n) -> `Assoc [("op", `String "size_ge"); ("val", `Intlit (Int64.to_string n))]
  (* MTime Ops (float) *)
  | MTime (TimeEq f) -> `Assoc [("op", `String "time_eq"); ("val", `Float f)]
  | MTime (TimeNe f) -> `Assoc [("op", `String "time_ne"); ("val", `Float f)]
  | MTime (TimeLt f) -> `Assoc [("op", `String "time_lt"); ("val", `Float f)]
  | MTime (TimeLe f) -> `Assoc [("op", `String "time_le"); ("val", `Float f)]
  | MTime (TimeGt f) -> `Assoc [("op", `String "time_gt"); ("val", `Float f)]
  | MTime (TimeGe f) -> `Assoc [("op", `String "time_ge"); ("val", `Float f)]
  (* Entropy Ops (float) *)
  | Entropy (FloatEq f) -> `Assoc [("op", `String "entropy_eq"); ("val", `Float f)]
  | Entropy (FloatNe f) -> `Assoc [("op", `String "entropy_ne"); ("val", `Float f)]
  | Entropy (FloatLt f) -> `Assoc [("op", `String "entropy_lt"); ("val", `Float f)]
  | Entropy (FloatLe f) -> `Assoc [("op", `String "entropy_le"); ("val", `Float f)]
  | Entropy (FloatGt f) -> `Assoc [("op", `String "entropy_gt"); ("val", `Float f)]
  | Entropy (FloatGe f) -> `Assoc [("op", `String "entropy_ge"); ("val", `Float f)]
  (* Perm Ops (int) *)
  | Perm (PermEq n) -> `Assoc [("op", `String "perm_eq"); ("val", `Int n)]
  | Perm (PermNe n) -> `Assoc [("op", `String "perm_ne"); ("val", `Int n)]
  | Perm (PermLt n) -> `Assoc [("op", `String "perm_lt"); ("val", `Int n)]
  | Perm (PermLe n) -> `Assoc [("op", `String "perm_le"); ("val", `Int n)]
  | Perm (PermGt n) -> `Assoc [("op", `String "perm_gt"); ("val", `Int n)]
  | Perm (PermGe n) -> `Assoc [("op", `String "perm_ge"); ("val", `Int n)] 

let rec json_to_expr (json : Yojson.Safe.t) : Ast.Typed.expr option =
  let open Yojson.Safe.Util in
  let open Ast.Typed in
  
  let compile_re s = 
    try Ok (Re.compile (Re.Pcre.re s)) 
    with _ -> Error "Regex compilation failed"
  in

  let op = member "op" json |> to_string_option in
  match op with
  | Some "true" -> Some True
  | Some "false" -> Some False
  | Some "not" -> (member "ptr" json |> json_to_expr |> Option.map (fun e -> Not e))
  | Some "and" -> 
      (match member "left" json |> json_to_expr, member "right" json |> json_to_expr with
      | Some e1, Some e2 -> Some (And (e1, e2)) | _ -> None)
  | Some "or" ->
      (match member "left" json |> json_to_expr, member "right" json |> json_to_expr with
      | Some e1, Some e2 -> Some (Or (e1, e2)) | _ -> None)
  
  | Some op ->
      let val_json = member "val" json in
      begin match op with
      (* String Ops *)
      | "name_eq" -> val_json |> to_string_option |> Option.map (fun s -> Name (StrEq s))
      | "name_ne" -> val_json |> to_string_option |> Option.map (fun s -> Name (StrNe s))
      | "name_re" -> 
          Option.bind (val_json |> to_string_option) (fun s -> 
             match compile_re s with Ok re -> Some (Name (StrRe (s, re))) | Error _ -> None)
      | "path_eq" -> val_json |> to_string_option |> Option.map (fun s -> Path (StrEq s))
      | "path_ne" -> val_json |> to_string_option |> Option.map (fun s -> Path (StrNe s))
      | "path_re" -> 
          Option.bind (val_json |> to_string_option) (fun s -> 
             match compile_re s with Ok re -> Some (Path (StrRe (s, re))) | Error _ -> None)
      | "content_eq" -> val_json |> to_string_option |> Option.map (fun s -> Content (StrEq s))
      | "content_ne" -> val_json |> to_string_option |> Option.map (fun s -> Content (StrNe s))
      | "content_re" ->
          Option.bind (val_json |> to_string_option) (fun s ->
             match compile_re s with Ok re -> Some (Content (StrRe (s, re))) | Error _ -> None)
      
      (* Type Ops *)
      | "type_eq" -> 
          Option.bind (val_json |> to_string_option) (function
            | "f" -> Some (Type (TypeEq File)) | "d" -> Some (Type (TypeEq Dir)) | "l" -> Some (Type (TypeEq Symlink)) | _ -> None)
      | "type_ne" ->
          Option.bind (val_json |> to_string_option) (function
            | "f" -> Some (Type (TypeNe File)) | "d" -> Some (Type (TypeNe Dir)) | "l" -> Some (Type (TypeNe Symlink)) | _ -> None)

      (* Numeric Ops/Time/Perm/Entropy *)
      | _ ->
          if String.starts_with ~prefix:"size_" op then
             let n_opt = match val_json with
               | `Int i -> Some (Int64.of_int i)
               | `Intlit s -> Some (Int64.of_string s)
               | _ -> None
             in
             Option.bind n_opt (fun n ->
               match op with
               | "size_eq" -> Some (Size (SizeEq n))
               | "size_ne" -> Some (Size (SizeNe n))
               | "size_lt" -> Some (Size (SizeLt n))
               | "size_le" -> Some (Size (SizeLe n))
               | "size_gt" -> Some (Size (SizeGt n))
               | "size_ge" -> Some (Size (SizeGe n))
               | _ -> None)
          else if String.starts_with ~prefix:"time_" op then
             Option.bind (val_json |> to_float_option) (fun f ->
               match op with
               | "time_eq" -> Some (MTime (TimeEq f))
               | "time_ne" -> Some (MTime (TimeNe f))
               | "time_lt" -> Some (MTime (TimeLt f))
               | "time_le" -> Some (MTime (TimeLe f))
               | "time_gt" -> Some (MTime (TimeGt f))
               | "time_ge" -> Some (MTime (TimeGe f))
               | _ -> None)
          else if String.starts_with ~prefix:"entropy_" op then
             Option.bind (val_json |> to_float_option) (fun f ->
               match op with
               | "entropy_eq" -> Some (Entropy (FloatEq f))
               | "entropy_ne" -> Some (Entropy (FloatNe f))
               | "entropy_lt" -> Some (Entropy (FloatLt f))
               | "entropy_le" -> Some (Entropy (FloatLe f))
               | "entropy_gt" -> Some (Entropy (FloatGt f))
               | "entropy_ge" -> Some (Entropy (FloatGe f))
               | _ -> None)
          else if String.starts_with ~prefix:"perm_" op then
             Option.bind (val_json |> to_int_option) (fun n ->
               match op with
               | "perm_eq" -> Some (Perm (PermEq n))
               | "perm_ne" -> Some (Perm (PermNe n))
               | "perm_lt" -> Some (Perm (PermLt n))
               | "perm_le" -> Some (Perm (PermLe n))
               | "perm_gt" -> Some (Perm (PermGt n))
               | "perm_ge" -> Some (Perm (PermGe n))
               | _ -> None)
          else None
      end
  | None -> None

let json_to_request json =
  let open Yojson.Safe.Util in
  match member "type" json |> to_string_option with
  | Some "stats" -> Ok Stats
  | Some "shutdown" -> Ok Shutdown
  | Some "query" -> 
      (match json_to_expr (member "expr" json) with
      | Some expr -> Ok (Query expr)
      | None -> Error "Invalid or unsupported query expression")
  | Some _ | None -> Error "Unknown request type"

let request_to_json = function
  | Stats -> `Assoc [("type", `String "stats")]
  | Shutdown -> `Assoc [("type", `String "shutdown")]
  | Query expr -> `Assoc [("type", `String "query"); ("expr", expr_to_json expr)]

let response_to_json = function
  | Success data -> `Assoc [("status", `String "ok"); ("data", data)]
  | Failure msg -> `Assoc [("status", `String "error"); ("message", `String msg)]

let handle_client flow handler =
  try
    let buf = Eio.Buf_read.of_flow ~max_size:4096 flow in
    while true do
      let line = Eio.Buf_read.line buf in
      match Yojson.Safe.from_string line with
      | json -> 
          let response = 
            match json_to_request json with
            | Ok req -> handler req
            | Error msg -> Failure msg
          in
          let resp_json = response_to_json response in
          let resp_str = Yojson.Safe.to_string resp_json ^ "\n" in
          Eio.Flow.copy_string resp_str flow
      | exception _ -> 
          Eio.Flow.copy_string (Yojson.Safe.to_string (response_to_json (Failure "Invalid JSON")) ^ "\n") flow
    done
  with End_of_file -> ()
  | e -> Printf.eprintf "Client disconnected: %s\n%!" (Printexc.to_string e)

let run ~sw ~net handler =
  let path = socket_path () in
  if Sys.file_exists path then Unix.unlink path;
  
  let addr = `Unix path in
  let socket = Eio.Net.listen net ~sw ~backlog:5 ~reuse_addr:true addr in
  
  Printf.printf "IPC Server listening on %s\n%!" path;
  
  while true do
    Eio.Net.accept_fork socket ~sw (fun flow _addr ->
      handle_client flow handler
    ) ~on_error:(fun ex -> Printf.eprintf "Connection error: %s\n%!" (Printexc.to_string ex))
  done

let json_to_response json =
  let open Yojson.Safe.Util in
  match member "status" json |> to_string_option with
  | Some "ok" -> Ok (Success (member "data" json))
  | Some "error" -> 
      let msg = member "message" json |> to_string_option |> Option.value ~default:"Unknown error" in
      Ok (Failure msg)
  | _ -> Error "Invalid response format"

(* Client Module *)
module Client = struct
  let connect ~sw ~net =
    let path = socket_path () in
    Eio.Net.connect ~sw net (`Unix path)

  let query ~sw ~net expr =
    try
      let flow = connect ~sw ~net in
      let req = Query expr in
      let req_json = request_to_json req in
      let req_str = Yojson.Safe.to_string req_json ^ "\n" in
      Eio.Flow.copy_string req_str flow;
      
      let buf = Eio.Buf_read.of_flow ~max_size:10_000_000 flow in (* 10MB response limit for now *)
      let line = Eio.Buf_read.line buf in
      match Yojson.Safe.from_string line with
      | json ->
          (match json_to_response json with
          | Ok (Success (`List results)) ->
               (* Convert generic JSON results back to Eval.entry structure *)
               let entries = List.filter_map (fun item ->
                 match item with
                 | `Assoc props ->
                     let get_str k = List.assoc_opt k props |> Option.map (function `String s -> s | _ -> "") in
                     let get_float k = List.assoc_opt k props |> Option.map (function `Float f -> f | _ -> 0.0) in
                     let get_int k = List.assoc_opt k props |> Option.map (function `Int i -> i | _ -> 0) in
                     
                     (match get_str "path", get_str "name", get_int "size", get_float "mtime" with
                     | Some path, Some name, Some size, Some mtime ->
                         Some { Eval.name; path; kind = Ast.File; size = Int64.of_int size; mtime; perm = 0o644 }
                     | _ -> None)
                 | _ -> None
               ) results in
               Ok entries
          | Ok (Success _) -> Error "Unexpected query result format"
          | Ok (Failure msg) -> Error ("Daemon error: " ^ msg)
          | Error e -> Error e)
      | exception _ -> Error "Failed to parse daemon response"
    with
    | ex -> 
        (* Eio exceptions are distinct *)
        Error (Printexc.to_string ex)

  let shutdown ~sw ~net =
    try
      let flow = connect ~sw ~net in
      let req = Shutdown in
      let req_json = request_to_json req in
      let req_str = Yojson.Safe.to_string req_json ^ "\n" in
      Eio.Flow.copy_string req_str flow;
      
      let buf = Eio.Buf_read.of_flow ~max_size:10_000 flow in
      let line = Eio.Buf_read.line buf in
      match Yojson.Safe.from_string line with
      | json ->
          (match json_to_response json with
          | Ok (Success (`String msg)) -> Ok msg
          | Ok (Success _) -> Ok "Daemon shutdown initiated"
          | Ok (Failure msg) -> Error msg
          | Error e -> Error e)
      | exception _ -> Error "Failed to parse daemon response"
    with
    | ex -> Error (Printexc.to_string ex)
end
