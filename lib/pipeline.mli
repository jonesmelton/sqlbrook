type skip =
  { kind : string (* leading keyword of the passed-through statement *)
  ; line : int (* 1-based line of its first token *)
  }

type result =
  { output : string
  ; had_passthrough : bool
  ; skips : skip list
  }

(* [Error msg] when the input cannot be lexed (msg locates the offending byte);
   [Ok result] otherwise. Statements outside the supported grammar are not
   errors — they pass through unchanged and set [had_passthrough]. *)
val format : string -> (result, string) Stdlib.result
