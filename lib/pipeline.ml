(* Public pipeline: string -> token list -> statement list -> string.

   Glues the four stages together. Returns the formatted text plus a flag
   indicating whether any statement fell back to passthrough, so the CLI can
   set a nonzero exit code. Module is named Pipeline (not Sqlbrook) to avoid
   colliding with the library's auto-generated wrapper module. *)

type result =
  { output : string
  ; had_passthrough : bool
  }

let format (_input : string) : result =
  failwith "Pipeline.format: not implemented"
