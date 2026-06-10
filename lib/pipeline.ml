(* Public pipeline: string -> token list -> statement list -> string.

   Glues the four stages together. Returns the formatted text plus a flag
   indicating whether any statement fell back to passthrough, so the CLI can
   set a nonzero exit code. Module is named Pipeline (not Sqlbrook) to avoid
   colliding with the library's auto-generated wrapper module. *)

type result =
  { output : string
  ; had_passthrough : bool
  }

(* Statements are separated by exactly one blank line, with a trailing
   newline at end of output. *)
let format (input : string) : result =
  let stmts = Skeleton.parse input (Lexer.tokens_with_spans input) in
  let render = function
    | Skeleton.Passthrough s -> s
    | _ -> failwith "Pipeline.format: layout not implemented"
  in
  let output =
    match stmts with
    | [] -> ""
    | _ -> String.concat "\n\n" (List.map render stmts) ^ "\n"
  in
  let had_passthrough =
    List.exists
      (function
        | Skeleton.Passthrough _ -> true
        | _ -> false)
      stmts
  in
  { output; had_passthrough }
;;
