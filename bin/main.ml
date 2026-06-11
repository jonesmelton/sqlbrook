let read_all (ic : in_channel) : string =
  let buf = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_channel buf ic 4096
     done
   with
   | End_of_file -> ());
  Buffer.contents buf
;;

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> read_all ic)
;;

let write_file (path : string) (data : string) : unit =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc data)
;;

(* One formatted source plus the name to use in diagnostics. *)
type formatted =
  { name : string
  ; source : string
  ; output : string
  ; had_passthrough : bool
  ; skips : Sqlbrook.Pipeline.skip list
  }

(* A lex error is non-SQL input far more often than a real lexer bug: a control
   byte, stray binary, or host-language interpolation that is not a SQLite bind
   parameter (:name @name $name ? ?NNN). Say so, so the caller knows where to
   look instead of suspecting sqlbrook. *)
let report_error ~name msg =
  Printf.eprintf "sqlbrook: %s: %s\n" name msg;
  (* The generic redirect only helps when we couldn't say more. A message that
     already names the dialect (a known other-dialect token) stands alone. *)
  let already_specific =
    let needle = "dialect is SQLite" in
    let nlen = String.length needle in
    let rec contains i =
      i + nlen <= String.length msg && (String.sub msg i nlen = needle || contains (i + 1))
    in
    contains 0
  in
  if not already_specific
  then
    Printf.eprintf
      "sqlbrook: %s: input is not lexable SQLite SQL; check for stray bytes or \
       host-language interpolation (use bind parameters instead)\n"
      name
;;

let format_source ~name ~source : (formatted, unit) result =
  match Sqlbrook.Pipeline.format source with
  | Ok { Sqlbrook.Pipeline.output; had_passthrough; skips } ->
    Ok { name; source; output; had_passthrough; skips }
  | Error msg ->
    report_error ~name msg;
    Error ()
;;

let warn_passthrough { name; skips; _ } =
  List.iter
    (fun { Sqlbrook.Pipeline.kind; line } ->
       Printf.eprintf
         "sqlbrook: %s: line %d: %s not yet formatted, passed through\n"
         name
         line
         kind)
    skips
;;

(* Exit codes: 0 ok, 1 --check found unformatted input, 2 usage/IO error,
   3 some statement passed through unformatted (an unsupported construct the
   formatter echoes verbatim). Default-strict: passthrough is never exit 0, so a
   caller can trust "exit 0 = fully formatted, nothing skipped". *)
let exit_ok = 0
let exit_check_failed = 1
let exit_usage = 2
let exit_passthrough = 3

(* The full operational contract: kept out of the terse --help and printed only
   on demand via --man, so the common --help stays scannable. *)
let man_page =
  {|sqlbrook(1)

DIALECT
  SQLite only. PostgreSQL/MySQL syntax (::cast, $$-quote, `backtick`) is
  reported as unlexable (exit 2), not formatted.

STATEMENTS
  Laid out:     select
  Passed through (echoed verbatim, exit 3): insert, update, delete, CTEs, DDL.

EXIT CODES
  0  all inputs fully formatted (or written); nothing passed through
  1  --check found at least one unformatted (but supported) input
  2  usage/I/O error, or input that isn't lexable SQLite SQL
  3  some statement passed through unformatted (an unsupported construct)
  Precedence when signals combine: 2 outranks 3 outranks 1.

STDOUT/STDERR
  stdout carries only valid formatted SQL (or nothing); all diagnostics go to
  stderr. Branch on the exit code. Unlexable input yields empty stdout and a
  located message on stderr, never a crash and never partial output.

EMBEDDED QUERIES
  The river is formatted at column 0; there is no --indent. Put embedded SQL in
  a leading-newline string literal so the statement starts at column 0, then
  extract -> run through sqlbrook -> splice back verbatim. Use bind parameters
  (:name @name $name ? ?NNN), not host-language interpolation.
|}
;;

let run man write check output files =
  if man
  then (
    print_string man_page;
    exit exit_ok);
  let results =
    match files with
    | [] -> [ format_source ~name:"<stdin>" ~source:(read_all stdin) ]
    | _ -> List.map (fun f -> format_source ~name:f ~source:(read_file f)) files
  in
  (* A lex failure in any input is exit 2. In -w mode the inputs that did lex
     are still rewritten (failed files left untouched); for stdout/-o/--check a
     failure means no partial product is emitted at all. *)
  let inputs = List.filter_map Result.to_option results in
  let any_failed = List.exists Result.is_error results in
  let any_passthrough = List.exists (fun r -> r.had_passthrough) inputs in
  List.iter warn_passthrough inputs;
  (* Precedence, most fundamental first: a lex/usage error (2) beats passthrough
     (3) beats --check's unformatted (1) beats ok (0). Passthrough means the tool
     cannot fully handle the input — louder than "not yet formatted", which -w
     would fix. Side effects (write/print) still happen for the lexable inputs;
     passthrough only changes the exit code, never whether output is emitted. *)
  match check, write, output with
  | true, _, _ ->
    let unformatted = List.filter (fun r -> r.output <> r.source) inputs in
    List.iter (fun r -> Printf.eprintf "sqlbrook: %s: not formatted\n" r.name) unformatted;
    if any_failed
    then exit_usage
    else if any_passthrough
    then exit_passthrough
    else if unformatted = []
    then exit_ok
    else exit_check_failed
  | false, true, _ ->
    if files = []
    then (
      prerr_endline "sqlbrook: --write needs file arguments; it cannot rewrite stdin";
      exit_usage)
    else (
      List.iter (fun r -> write_file r.name r.output) inputs;
      if any_failed
      then exit_usage
      else if any_passthrough
      then exit_passthrough
      else exit_ok)
  | false, false, Some path ->
    if any_failed
    then exit_usage
    else (
      write_file path (String.concat "" (List.map (fun r -> r.output) inputs));
      if any_passthrough then exit_passthrough else exit_ok)
  | false, false, None ->
    if any_failed
    then exit_usage
    else (
      List.iter (fun r -> print_string r.output) inputs;
      if any_passthrough then exit_passthrough else exit_ok)
;;

open Cmdliner

let man =
  let doc =
    "Print the full operational contract (dialect, statement scope, exit codes, \
     stdout/stderr discipline, embedded-query convention) and exit."
  in
  Arg.(value & flag & info [ "man" ] ~doc)
;;

let write =
  let doc = "Rewrite each input $(i,FILE) in place instead of writing to stdout." in
  Arg.(value & flag & info [ "w"; "write" ] ~doc)
;;

let check =
  let doc =
    "Do not write anything; exit with status 1 if any input is not already formatted \
     (status 3 takes precedence if any input has an unsupported construct that passes \
     through). Affected inputs are reported on stderr."
  in
  Arg.(value & flag & info [ "check" ] ~doc)
;;

let output =
  let doc = "Write the concatenated formatted output to $(docv) instead of stdout." in
  Arg.(value & opt (some string) None & info [ "o"; "output" ] ~docv:"FILE" ~doc)
;;

let files =
  let doc = "SQL files to format. With none, read from stdin." in
  Arg.(value & pos_all string [] & info [] ~docv:"FILE" ~doc)
;;

let cmd =
  let doc = "a whole-statement SQL formatter for the river style" in
  let man_block =
    [ `S Manpage.s_description
    ; `P
        "$(tname) reformats SQL into the \"river\" style: lowercase keywords, clause \
         keywords right-aligned to a common river column, leading commas, one expression \
         per line. $(b,Dialect: SQLite only.)"
    ; `P
        "$(b,Lays out:) select. $(b,Passes through) (echoed verbatim, exit 3): insert, \
         update, delete, CTEs, DDL. Other dialects' syntax is reported as unlexable \
         (exit 2)."
    ; `P "Run $(b,--man) for the full exit-code and embedded-query contract."
    ; `S Manpage.s_examples
    ; `P "Format files to stdout:"
    ; `Pre "  \\$ $(tname) a.sql b.sql"
    ; `P "Format stdin:"
    ; `Pre "  \\$ $(tname) < a.sql"
    ; `P "Rewrite files in place:"
    ; `Pre "  \\$ $(tname) -w a.sql"
    ; `P "Check formatting in CI (no output, nonzero exit if unformatted):"
    ; `Pre "  \\$ $(tname) --check *.sql"
    ]
  in
  let exits =
    [ Cmd.Exit.info
        exit_ok
        ~doc:"all inputs fully formatted (or written); nothing passed through."
    ; Cmd.Exit.info
        exit_check_failed
        ~doc:"$(b,--check) found at least one unformatted input."
    ; Cmd.Exit.info exit_usage ~doc:"a usage, I/O, or unlexable-input error occurred."
    ; Cmd.Exit.info
        exit_passthrough
        ~doc:
          "some statement passed through unformatted (an unsupported construct). Output \
           is still emitted unchanged; this status only signals the skip."
    ]
  in
  let info = Cmd.info "sqlbrook" ~version:"0.1.0" ~doc ~man:man_block ~exits in
  Cmd.v info Term.(const run $ man $ write $ check $ output $ files)
;;

let () = exit (Cmd.eval' ~term_err:exit_usage cmd)
