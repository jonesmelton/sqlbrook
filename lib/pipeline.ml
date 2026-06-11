(* Named Pipeline, not Sqlbrook, to avoid colliding with the library's
   auto-generated wrapper module. *)

type skip =
  { kind : string
  ; line : int
  }

type result =
  { output : string
  ; had_passthrough : bool
  ; skips : skip list
  }

(* 1-based line of a byte offset: one newline scan over the prefix. *)
let line_of_offset (src : string) (offset : int) : int =
  let n = min offset (String.length src) in
  let count = ref 1 in
  for i = 0 to n - 1 do
    if src.[i] = '\n' then incr count
  done;
  !count
;;

let format (input : string) : (result, string) Stdlib.result =
  match Lexer.tokens_with_spans input with
  | exception Lexer.Error msg -> Error msg
  | tokens ->
    let parsed = Skeleton.parse input tokens in
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
    let skips =
      List.filter_map
        (fun { Skeleton.stmt; _ } ->
           match stmt with
           | Skeleton.Passthrough { kind; offset; _ } ->
             Some { kind; line = line_of_offset input offset }
           | _ -> None)
        parsed
    in
    Ok { output; had_passthrough = skips <> []; skips }
;;
