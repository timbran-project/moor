# MOORC binary selection via environment variable MOORC_TYPE
# Options: cargo (default), direct, docker
MOORC_TYPE ?= cargo
HEADLESS_FILTERS ?= "\#90000" "\#90001" "\#90002" "\#90003" "\#90004" "\#90005" "\#90006"
HEADLESS_TIMEOUT ?= 10
HEADLESS_SRC_DIRECTORY ?= .runtime-headless-src

# DEBUG controls whether to run moorc under gdb
# Set DEBUG=1 to enable gdb debugging
DEBUG ?= 0

# Docker image name for MOORC_TYPE=docker
MOORC_IMAGE ?= moor-moor-daemon

OPTIONS = --use-boolean-returns true \
          --use-symbols-in-builtins true \
          --custom-errors true \
          --use-uuobjids true \
          --anonymous-objects true

ifeq ($(MOORC_TYPE),cargo)
SRC_DIRECTORY = src
OUTPUT_DIRECTORY = .
ifeq ($(DEBUG),1)
MOORC = gdb --batch --ex "handle SIGUSR1 nostop noprint pass" --ex run --ex bt --ex quit --args cargo run -p moorc -- \
	$(OPTIONS)
else
MOORC = cargo run -p moorc -- $(OPTIONS)
endif
else ifeq ($(MOORC_TYPE),direct)
SRC_DIRECTORY = src
OUTPUT_DIRECTORY = .
MOORC = ../moor/target/debug/moorc $(OPTIONS)
else ifeq ($(MOORC_TYPE),docker)
SRC_DIRECTORY = /work/src
OUTPUT_DIRECTORY = /work
MOORC = docker run --rm -v $(CURDIR):/work -w /work $(MOORC_IMAGE) /moor/moorc $(OPTIONS)
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
	cp -r gen.objdir/* ./src/

test:  $(wildcard src/*.moo)
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY)  --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir \
	--test-wizard=2 --test-programmer=6 --test-player=4 --run-tests true

runtime-headless: $(wildcard src/*.moo src/*/*.moo tests/headless/*.moo)
	rm -rf $(HEADLESS_SRC_DIRECTORY)
	mkdir -p $(HEADLESS_SRC_DIRECTORY)
	rsync -a src/ $(HEADLESS_SRC_DIRECTORY)/
	rsync -a tests/headless/ $(HEADLESS_SRC_DIRECTORY)/
	cat tests/headless/headless_constants.moo >> $(HEADLESS_SRC_DIRECTORY)/constants.moo
	rm -f $(HEADLESS_SRC_DIRECTORY)/headless_constants.moo
	set -e; for filter in $(HEADLESS_FILTERS); do \
		$(MOORC) --src-objdef-dir $(HEADLESS_SRC_DIRECTORY)  --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir \
		--test-wizard=2 --test-programmer=6 --test-player=4 --run-tests true \
		--test-filter "$$filter" --test-timeout $(HEADLESS_TIMEOUT); \
	done

clean:
	rm -f gen.moo-textdump
	rm -rf gen.objdir
	rm -rf $(HEADLESS_SRC_DIRECTORY)

output: gen.moo-textdump
