(* CLI entry point.

   Reads stdin or file args, writes formatted SQL to stdout. Warns on stderr
   when statements fall back to passthrough. A nonzero exit for passthrough
   (to gate CI) is deferred to the CLI-polish milestone: while layout stages
   are unimplemented everything passes through, and a nonzero exit would fail
   every golden rule. In-place editing (-i) is deferred. *)

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

let () =
  let format_one name src =
    let r : Sqlbrook.Pipeline.result = Sqlbrook.Pipeline.format src in
    print_string r.output;
    if r.had_passthrough
    then Printf.eprintf "sqlbrook: %s: some statements passed through unformatted\n" name
  in
  match Array.to_list Sys.argv with
  | _ :: (_ :: _ as files) ->
    List.iter
      (fun file ->
         let ic = open_in_bin file in
         let src = read_all ic in
         close_in ic;
         format_one file src)
      files
  | _ -> format_one "<stdin>" (read_all stdin)
;;
