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
  let parsed = Skeleton.parse input (Lexer.tokens_with_spans input) in
  let render { Skeleton.comments; stmt } =
    let body = Emit.render_stmt stmt in
    match comments with
    | [] -> body
    | cs -> String.concat "\n" cs ^ "\n" ^ body
  in
  let output =
    match parsed with
    | [] -> ""
    | _ -> String.concat "\n\n" (List.map render parsed) ^ "\n"
  in
  let had_passthrough =
    List.exists
      (fun { Skeleton.stmt; _ } ->
         match stmt with
         | Skeleton.Passthrough _ -> true
         | _ -> false)
      parsed
  in
  { output; had_passthrough }
;;
