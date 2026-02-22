(** Inter-Process Communication (IPC) for Quasifind.

    This module handles the Unix Domain Socket server and client communication
    used by the quasifind daemon. It provides a JSON-RPC-like interface to 
    submit evaluation requests, fetch stats, and gracefully shutdown the daemon. *)

(** Represents a request sent from the CLI client to the daemon. *)
type request =
  | Query of Ast.Typed.expr (** A typed AST expression to evaluate against the VFS *)
  | Stats                   (** Request internal daemon statistics (e.g., node count) *)
  | Shutdown                (** Request the daemon to terminate immediately *)

(** Represents a response sent from the daemon back to the CLI client. *)
type response = 
  | Success of Yojson.Safe.t (** A successful response payload in JSON format *)
  | Failure of string        (** An error message if the request failed *)

(** [socket_path ()] returns the Unix domain socket path used for IPC. *)
val socket_path : unit -> string

(** [expr_to_json expr] serializes an AST expression into a JSON object. *)
val expr_to_json : Ast.Typed.expr -> Yojson.Safe.t

(** [json_to_expr json] parses a JSON object into an AST expression. *)
val json_to_expr : Yojson.Safe.t -> Ast.Typed.expr option

(** [json_to_request json] parses a JSON object into an IPC request. *)
val json_to_request : Yojson.Safe.t -> (request, string) result

(** [request_to_json req] serializes an IPC request into a JSON object. *)
val request_to_json : request -> Yojson.Safe.t

(** [json_to_response json] parses a JSON object into an IPC response. *)
val json_to_response : Yojson.Safe.t -> (response, string) result

(** [response_to_json resp] serializes an IPC response into a JSON object. *)
val response_to_json : response -> Yojson.Safe.t

(** [run ~sw ~net ~clock ?shutdown_flag handler] starts the IPC server listening
    on the standard Unix Domain Socket path. 
    
    @param sw The Eio switch bounding the server's lifetime.
    @param net The network provider for listening on the socket.
    @param clock The clock provider for handling timeouts.
    @param shutdown_flag A boolean reference that, when set to true, will cause the server to stop accepting connections.
    @param handler A callback function that receives a [request] and produces a [response]. *)
val run : 
  sw:Eio.Switch.t -> 
  net:_ Eio.Net.t -> 
  clock:_ Eio.Time.clock -> 
  ?shutdown_flag:bool ref -> 
  (request -> response) -> unit

(** The [Client] module provides functions for the CLI to communicate with a running daemon. *)
module Client : sig
  (** [query ~sw ~net expr] sends a [Query expr] request to the running daemon
      and waits for the evaluated file entries.
      
      Returns a list of matching [Eval.entry] objects, or an error message. *)
  val query : 
    sw:Eio.Switch.t -> 
    net:_ Eio.Net.t -> 
    Ast.Typed.expr -> (Eval.entry list, string) result

  (** [shutdown ~sw ~net] sends a [Shutdown] request to the daemon.
      Returns a confirmation message or an error. *)
  val shutdown : 
    sw:Eio.Switch.t -> 
    net:_ Eio.Net.t -> (string, string) result
end
