(lang dune 3.0)

(name sqlbrook)

(license MIT)

(authors "Jones Melton")

(package
 (name sqlbrook)
 (synopsis "A whole-statement SQL formatter for the river style")
 (depends
  (ocaml
   (>= 5.4))
  cmdliner
  (ppx_expect :with-test)))
