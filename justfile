# sqlbrook dev tasks. All recipes go through the local opam switch (_opam).

# list recipes
default:
    @just --list

# compile everything
build:
    opam exec -- dune build

# run the full suite: unit/expect tests, invariants, golden diffs
test:
    opam exec -- dune test

# accept current formatter output as the new golden expectation
promote:
    opam exec -- dune promote

# rebuild and rerun tests on file changes
watch:
    opam exec -- dune test --watch

# format SQL from files (or stdin if no args), e.g.: just fmt examples/lore.sql
fmt *files:
    opam exec -- dune exec --no-print-directory sqlbrook -- {{files}}

# build and install the binary to ~/.local/bin
install: build
    opam exec -- dune install --prefix ~/.local --sections bin

# remove build artifacts
clean:
    opam exec -- dune clean
