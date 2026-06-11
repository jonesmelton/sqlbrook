(lang dune 3.0)

(cram enable)

(generate_opam_files true)

(name sqlbrook)

(license MIT)

(authors "Jones Melton")

(maintainers "Jones Melton <shavah@gmail.com>")

(source
 (github jonesmelton/sqlbrook))

(package
 (name sqlbrook)
 (synopsis "A whole-statement SQL formatter for the river style")
 (description
  "sqlbrook reformats SQLite SQL into the \"river\" style: lowercase keywords, clause keywords right-aligned to a common river column, leading commas, one expression per line.")
 (depends
  (ocaml
   (>= 5.4))
  cmdliner
  (ppx_expect :with-test)))
