(** Ghost File Detection.

    This module identifies "ghost files" — files that have been deleted from 
    the filesystem (unlinked) but are still held open by a running process. 
    This is often useful for finding hidden malware or leaked storage. *)

(** [scan root] uses the `lsof` system utility to find unlinked files 
    that fall under the given [root] directory. 
    
    @return A list of paths corresponding to the detected ghost files.
            Returns an empty list if `lsof` is unavailable or fails. *)
val scan : string -> string list

(** Parses the raw output of the `lsof` command. Exposed for testing. *)
val parse_lsof_output : string list -> string -> string list
