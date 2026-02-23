(* String Interning using Generational Cache *)
(* Deduplicates strings to save memory in VFS, with a strict size limit *)

let max_size = 65536
let prev_table = ref (Hashtbl.create max_size)
let curr_table = ref (Hashtbl.create max_size)
let mutex = Mutex.create ()

(* Intern a string: returns the shared physical instance if it exists.
   Uses a two-generation cache to prevent unbounded memory growth while
   keeping recently used strings. *)
let intern s =
  Mutex.lock mutex;
  let res =
    match Hashtbl.find_opt !curr_table s with
    | Some res -> res
    | None ->
        match Hashtbl.find_opt !prev_table s with
        | Some res ->
            Hashtbl.add !curr_table s res;
            if Hashtbl.length !curr_table >= max_size then begin
              prev_table := !curr_table;
              curr_table := Hashtbl.create max_size;
            end;
            res
        | None ->
            Hashtbl.add !curr_table s s;
            if Hashtbl.length !curr_table >= max_size then begin
              prev_table := !curr_table;
              curr_table := Hashtbl.create max_size;
            end;
            s
  in
  Mutex.unlock mutex;
  res
