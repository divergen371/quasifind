(lang dune 3.21)

(name quasifind)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name <author@example.com>")

(maintainers "Maintainer Name <maintainer@example.com>")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name quasifind)
 (synopsis "A find-like filesystem query engine with a typed DSL")
 (description
  "Quasi-find is an experimental, typed DSL-based alternative to find")
 (depends
  ocaml
  re
  angstrom
  dune
  eio
  eio_main
  ppx_deriving
  alcotest
  cmdliner
  yojson
  qcheck
  qcheck-alcotest
  saturn)
 (tags
  ("add topics" "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
