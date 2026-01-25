(* Suspicious file detection rules *)
open Ast.Untyped

let rules () = 
  let hidden_exec = 
    Cmp ("name", RegexMatch, VRegex "^\\..*\\.(sh|py|exe)$") 
  in
  let dangerous_perm = (* 777 permission *)
    Cmp ("perm", Eq, VInt 511L) (* 0o777 *)
  in
  let suid_files = (* Simple check: large permission value implies special bits *)
    Cmp ("perm", Ge, VInt 2048L) (* 0o4000 *)
  in
  let huge_tmp = 
    And (
      Cmp ("path", RegexMatch, VRegex "^/tmp/.*"),
      Cmp ("size", Gt, VSize (100L, MB))
    )
  in
  let suspicious_ext =
    Cmp ("name", RegexMatch, VRegex ".*\\.(payload|backdoor|exploit)$")
  in
  let base64_name =
    Cmp ("name", RegexMatch, VRegex "^[A-Za-z0-9+/=]{30,}\\.[a-z]+$")
  in
  
  Or (
    hidden_exec,
    Or (
      dangerous_perm,
      Or (
        suid_files,
        Or (
          huge_tmp,
          Or (suspicious_ext, base64_name)
        )
      )
    )
  )
