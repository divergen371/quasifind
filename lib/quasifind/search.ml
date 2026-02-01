(* search.ml - Bindings to C search stubs *)

(* Returns:
   1: Match
   0: No Match
   -1: Error / Fallback
*)
external search_regex_c : string -> string -> int = "caml_search_regex"

type search_result = 
  | Match 
  | NoMatch 
  | Fallback

let regex (path : string) (pattern : string) : search_result =
  match search_regex_c path pattern with
  | 1 -> Match
  | 0 -> NoMatch
  | _ -> Fallback
