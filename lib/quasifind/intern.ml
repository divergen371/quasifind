(* String Interning using Weak Hash Table *)
(* Deduplicates strings to save memory in VFS *)

module StringHash = struct
  type t = string
  let equal = String.equal
  let hash = Hashtbl.hash
end

module WeakString = Weak.Make(StringHash)

let table = WeakString.create 4096
let mutex = Mutex.create ()

(* Intern a string: returns the shared physical instance if it exists *)
let intern s = 
  Mutex.lock mutex;
  let res = WeakString.merge table s in
  Mutex.unlock mutex;
  res
