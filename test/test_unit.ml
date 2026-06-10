(* Unit-level snapshots and invariants (ppx_expect).

   Covers: multi-word keyword lexing, placeholder forms, quoted identifiers
   and >= 0x80 bytes, individual clause layouts, passthrough-with-warning
   behavior, and the cross-cutting invariants:
     - token preservation:  lex (fmt x) = lex x
     - idempotence:         fmt (fmt x) = fmt x

   All cases are stubbed; bodies land with their milestones. *)

open Sqlbrook

let%expect_test "lexer: multi-word keyword normalization" =
  ignore Lexer.tokens_of_string;
  [%expect {| |}]

let%expect_test "lexer: placeholder forms (:name @name $name ?NNN ?)" =
  [%expect {| |}]

let%expect_test "lexer: quoted identifiers and non-ascii bytes pass through" =
  [%expect {| |}]

let%expect_test "skeleton: select splits into clauses" =
  ignore Skeleton.parse;
  [%expect {| |}]

let%expect_test "emit: select river layout" =
  ignore Emit.format;
  ignore Measure.river_width;
  [%expect {| |}]

let%expect_test "passthrough: unsupported construct emitted unchanged" =
  ignore Pipeline.format;
  [%expect {| |}]

(* Invariant: tokenizing formatted output yields the same tokens as the input. *)
let%expect_test "invariant: token preservation" =
  [%expect {| |}]

(* Invariant: formatting is a fixed point after the first application. *)
let%expect_test "invariant: idempotence" =
  [%expect {| |}]
