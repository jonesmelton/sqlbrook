(lang dune 3.0)

(name sqlbrook)

(package
 (name sqlbrook)
 (synopsis "A whole-statement SQL formatter for the river style")
 (depends
  (ocaml
   (>= 5.4))
  (ppx_expect :with-test)))
