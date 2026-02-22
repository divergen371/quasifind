(** Custom Detection Rule Management.

    This module handles the loading and saving of custom detection rules 
    (stored in JSON format in the user's config directory). *)

(** Represents a single detection rule definition. *)
type rule_def = {
  name : string;    (** Human-readable name for the rule *)
  expr : string;    (** The quasifind query expression string *)
}

(** Represents a collection of rules with a version. *)
type rule_set = {
  version : string;
  rules : rule_def list;
}

(** Global default rule set, containing basic webshell and reverse shell detection. *)
val default_rule_set : rule_set

(** [save_rules rule_set] serializes the [rule_set] to the user's config directory as JSON. *)
val save_rules : rule_set -> unit

(** [load_rules ()] attempts to read the `rules.json` file from the config directory.
    If it doesn't exist, it creates it using [default_rule_set].
    
    @return [Some rule_set] on success, or [None] if parsing fails. *)
val load_rules : unit -> rule_set option

(** [reset_to_default ()] overwrites the current rules file with [default_rule_set]. *)
val reset_to_default : unit -> unit
