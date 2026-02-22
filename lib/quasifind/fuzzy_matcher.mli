(** Fuzzy String Matching.

    This module provides a heuristic implementation of the Smith-Waterman 
    algorithm with affine gap penalties for fuzzy string matching, optimized 
    for searching file paths. *)

(** [match_score ~query ~candidate] calculates a fuzzy match score for [candidate] 
    against [query]. 

    @return [Some score] if [query] is a subsequence of [candidate], where 
            a higher score indicates a better match. [None] otherwise. *)
val match_score : query:string -> candidate:string -> int option

(** [rank ~query ~candidates] filters and sorts a list of [candidates].
    
    Candidates that do not match the [query] are removed. The remaining 
    candidates are returned sorted by their fuzzy match score in descending 
    order (best matches first). *)
val rank : query:string -> candidates:string list -> string list
