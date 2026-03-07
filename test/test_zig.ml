open Quasifind

let () =
  Printf.printf "Verifying Zig bridge...\n";
  let msg = Zig_poc.zig_dummy_hello () in
  Printf.printf "Zig says: %s\n%!" msg
