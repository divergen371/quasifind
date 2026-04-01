open Quasifind
let () =
  let q = "name =~ \".*\\\\.ml$\"" in
  match Parser.parse q with
  | Ok (Ast.Untyped.Cmp ("name", Ast.RegexMatch, Ast.Untyped.VStr s)) ->
      Printf.printf "Parsed Regex string: %S\n%!" s;
      let re = Re.Pcre.re s |> Re.compile in
      let matched = Re.execp re "foo.ml" in
      Printf.printf "Re executes: foo.ml = %b\n%!" matched;
      let suffix = Ast.Typed.Planner.try_extract_suffix s in
      (match suffix with
      | Some suf -> Printf.printf "Extracted suffix: %S\n%!" suf
      | None -> Printf.printf "No suffix extracted\n%!")
  | _ -> Printf.printf "Parse failed\n%!"
