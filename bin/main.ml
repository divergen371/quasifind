let () =
  let input =
    {|(name =~ /.*\.log$/ && type == file && size > 10MB) || (path =~ "^src/" && mtime < 7d)|}
  in
  match Quasifind.Parser.parse input with
  | Ok _ast -> print_endline "parsed OK"
  | Error e -> prerr_endline ("parse error: " ^ e)
