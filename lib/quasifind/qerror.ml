type t =
  | ParseError of string
  | TypeError of string
  | FileError of string * string
  | DaemonError of string
  | PermissionDenied of string
  | GeneralError of string

let to_string = function
  | ParseError msg -> 
      Printf.sprintf "Syntax Error: %s" msg
  | TypeError msg ->
      Printf.sprintf "Type Error: %s" msg
  | FileError (path, reason) ->
      Printf.sprintf "File Error: Cannot access '%s' (%s)" path reason
  | DaemonError msg ->
      Printf.sprintf "Daemon Error: %s" msg
  | PermissionDenied path ->
      Printf.sprintf "Permission Denied: '%s'" path
  | GeneralError msg ->
      Printf.sprintf "Error: %s" msg

let to_exit_code = function
  | GeneralError _ | FileError _ | PermissionDenied _ -> 1
  | ParseError _ | TypeError _ -> 2
  | DaemonError _ -> 3
