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
  }

let format_source ~name ~source =
  let { Sqlbrook.Pipeline.output; had_passthrough } = Sqlbrook.Pipeline.format source in
  { name; source; output; had_passthrough }
;;

let warn_passthrough { name; had_passthrough; _ } =
  if had_passthrough
  then Printf.eprintf "sqlbrook: %s: some statements passed through unformatted\n" name
;;

(* Exit codes: 0 ok, 1 --check found unformatted input, 2 usage/IO error. *)
let exit_ok = 0
let exit_check_failed = 1
let exit_usage = 2

let run write check output files =
  let inputs =
    match files with
    | [] -> [ format_source ~name:"<stdin>" ~source:(read_all stdin) ]
    | _ -> List.map (fun f -> format_source ~name:f ~source:(read_file f)) files
  in
  List.iter warn_passthrough inputs;
  match check, write, output with
  | true, _, _ ->
    let unformatted = List.filter (fun r -> r.output <> r.source) inputs in
    List.iter (fun r -> Printf.eprintf "sqlbrook: %s: not formatted\n" r.name) unformatted;
    if unformatted = [] then exit_ok else exit_check_failed
  | false, true, _ ->
    if files = []
    then (
      prerr_endline "sqlbrook: --write needs file arguments; it cannot rewrite stdin";
      exit_usage)
    else (
      List.iter (fun r -> write_file r.name r.output) inputs;
      exit_ok)
  | false, false, Some path ->
    write_file path (String.concat "" (List.map (fun r -> r.output) inputs));
    exit_ok
  | false, false, None ->
    List.iter (fun r -> print_string r.output) inputs;
    exit_ok
;;

open Cmdliner

let write =
  let doc = "Rewrite each input $(i,FILE) in place instead of writing to stdout." in
  Arg.(value & flag & info [ "w"; "write" ] ~doc)
;;

let check =
  let doc =
    "Do not write anything; exit with status 1 if any input is not already formatted. \
     Names of unformatted inputs are reported on stderr."
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
  let man =
    [ `S Manpage.s_description
    ; `P
        "$(tname) reformats SQLite SQL into the \"river\" style: lowercase keywords, \
         clause keywords right-aligned to a common river column, leading commas, one \
         expression per line."
    ; `P
        "Statements the formatter does not yet handle (insert, update, CTEs, DDL) are \
         emitted unchanged, with a warning on stderr."
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
    [ Cmd.Exit.info exit_ok ~doc:"all inputs formatted (or written) successfully."
    ; Cmd.Exit.info
        exit_check_failed
        ~doc:"$(b,--check) found at least one unformatted input."
    ; Cmd.Exit.info exit_usage ~doc:"a usage or I/O error occurred."
    ]
  in
  let info = Cmd.info "sqlbrook" ~version:"0.1.0" ~doc ~man ~exits in
  Cmd.v info Term.(const run $ write $ check $ output $ files)
;;

let () = exit (Cmd.eval' ~term_err:exit_usage cmd)
