Exit-code contract for the sqlbrook CLI.
0 = fully formatted (nothing skipped); 1 = --check found unformatted input;
2 = usage error or input that isn't lexable SQLite SQL; 3 = default-strict,
some statement passed through unformatted.

A formatted select round-trips to exit 0 with no stderr:

  $ printf 'select a\n  from t\n       ;\n' | sqlbrook
  select a
    from t
         ;

An unsupported construct still echoes on stdout (whole-file integrity) but the
exit is 3, not 0 — the agent's signal that something was skipped:

  $ printf 'select a from t union select b from u;' | sqlbrook
  select a from t union select b from u;
  sqlbrook: <stdin>: line 1: select not yet formatted, passed through
  [3]

Unlexable input: exit 2, empty stdout, located message plus redirect hint:

  $ printf 'select \001 from t;' | sqlbrook
  sqlbrook: <stdin>: unexpected byte '\001' at offset 7
  sqlbrook: <stdin>: input is not lexable SQLite SQL; check for stray bytes or host-language interpolation (use bind parameters instead)
  [2]

--check on already-formatted input: exit 0.

  $ printf 'select a\n  from t\n       ;\n' > formatted.sql
  $ sqlbrook --check formatted.sql

--check on unformatted-but-supported input: exit 1.

  $ printf 'select a from t;' > unformatted.sql
  $ sqlbrook --check unformatted.sql
  sqlbrook: unformatted.sql: not formatted
  [1]

--check where passthrough is present: passthrough wins (3), even though the
input is also "not formatted":

  $ printf 'select a from t union select b from u;' > unsupported.sql
  $ sqlbrook --check unsupported.sql
  sqlbrook: unsupported.sql: line 1: select not yet formatted, passed through
  sqlbrook: unsupported.sql: not formatted
  [3]

-w isolates failures: the lexable file is rewritten, the unlexable one is left
untouched, and the run exits 2.

  $ printf 'select a from t;' > good.sql
  $ printf 'select \001 from t;' > bad.sql
  $ cp bad.sql bad.orig
  $ sqlbrook -w good.sql bad.sql
  sqlbrook: bad.sql: unexpected byte '\001' at offset 7
  sqlbrook: bad.sql: input is not lexable SQLite SQL; check for stray bytes or host-language interpolation (use bind parameters instead)
  [2]
  $ cat good.sql
  select a
    from t
         ;
  $ cmp bad.sql bad.orig && echo untouched
  untouched
