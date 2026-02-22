(** Daemon execution and lifecycle management for Quasifind.

    This module handles the initialization, event loop, and graceful shutdown
    of the quasifind background daemon. It coordinates the Virtual File System (VFS),
    the file watcher, and the IPC server. *)

(** [run ~root] starts the quasifind daemon monitoring the standard configured directories,
    or the specified [root] directory. 
    
    This function blocks indefinitely while the daemon is running, 
    managing Eio fibers for IPC, file watching, and heartbeats. 
    It will gracefully exit and save the VFS state to disk if an IPC shutdown 
    request is received. *)
val run : root:string -> unit
