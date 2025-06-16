# MOORC binary selection via environment variable MOORC_TYPE
# Options: cargo (default), direct, docker
MOORC_TYPE ?= cargo

ifeq ($(MOORC_TYPE),cargo)
SRC_DIRECTORY = src
TEST_DIRECTORY = tests
OUTPUT_DIRECTORY = .
MOORC = cargo run -p moorc -- \
	--use-boolean-returns true \
	--use-symbols-in-builtins true \
	--custom-errors true
else ifeq ($(MOORC_TYPE),direct)
SRC_DIRECTORY = src
TEST_DIRECTORY = tests
OUTPUT_DIRECTORY = .
MOORC = ../moor/target/debug/moorc \
	--use-boolean-returns true \
	--use-symbols-in-builtins true \
	--custom-errors true
else ifeq ($(MOORC_TYPE),docker)
SRC_DIRECTORY = /work/src
TEST_DIRECTORY = /work/tests
OUTPUT_DIRECTORY = /work
MOORC = docker run -v .:$(OUTPUT_DIRECTORY) -i ghcr.io/rdaum/moor:release ./moorc \
	--use-boolean-returns true \
	--use-symbols-in-builtins true \
	--custom-errors true
endif

# Target to generate an old-style MOO textdump from the compilation of the
# objdef style sources in the local directory. This is the default target,
# and is intended mainly just to do a validation/compilation pass.
gen.moo-textdump: $(wildcard src/*.moo)
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY) --out-textdump $(OUTPUT_DIRECTORY)/$@

# Target to generate a new objdef dump from the compilation of the local
# directory.
gen.objdir: $(wildcard src/*.moo)
	rm -rf gen.objdir
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY) --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir

# Builds a new objdef dump and then copies over the local working sources.
# WARNING: this is destructive to local changes you might have -- it *will*
# overwrite them -- and is meant  mainly as the last step before performing a
# git commit.
rebuild: gen.objdir
	cp gen.objdir/*.moo ./src

test:  $(wildcard src/*.moo)
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY)  --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir \
	--test-directory $(TEST_DIRECTORY) --test-wizard=2 --test-programmer=6 --test-player=4 --run-tests true

clean:
	rm -f gen.moo-textdump
	rm -rf gen.objdir

output: gen.moo-textdump

