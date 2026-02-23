module PatternHash = Hashtbl.Make(String)

let max_cache_size = 1024
let cache = PatternHash.create max_cache_size
let mutex = Mutex.create ()

let compile pattern =
  Mutex.lock mutex;
  let re =
    match PatternHash.find_opt cache pattern with
    | Some re -> re
    | None ->
        let re = Re.compile (Re.Pcre.re pattern) in
        if PatternHash.length cache >= max_cache_size then
          PatternHash.clear cache; (* Simple evict-all strategy to avoid memory leak *)
        PatternHash.add cache pattern re;
        re
  in
  Mutex.unlock mutex;
  re
