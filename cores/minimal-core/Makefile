# MOORC binary selection via environment variable MOORC_TYPE
# Options: cargo (default), direct, docker
MOORC_TYPE ?= cargo

# DEBUG controls whether to run moorc under gdb.
# Set DEBUG=1 to enable gdb debugging.
DEBUG ?= 0

# Docker image name for MOORC_TYPE=docker
MOORC_IMAGE ?= moor-moor-daemon

OPTIONS = --use-boolean-returns true \
          --use-symbols-in-builtins true \
          --custom-errors true \
          --use-uuobjids true

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
MOORC = ../../target/debug/moorc $(OPTIONS)
else ifeq ($(MOORC_TYPE),docker)
SRC_DIRECTORY = /work/src
OUTPUT_DIRECTORY = /work
MOORC = docker run --rm -v $(CURDIR):/work -w /work $(MOORC_IMAGE) /moor/moorc $(OPTIONS)
endif

.PHONY: rebuild output test clean

SRC_FILES := $(wildcard src/*.moo src/*/*.moo)

# Build a normalized objdef dump from the local source tree.
gen.objdir: $(SRC_FILES)
	rm -rf gen.objdir
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY) --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir

rebuild: gen.objdir
	test -d gen.objdir
	rm -rf src
	mkdir -p src
	cp -r gen.objdir/* ./src/

test: $(SRC_FILES)
	rm -rf gen.objdir
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY) --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir \
	--test-wizard=3 --test-programmer=3 --test-player=3 --run-tests true

clean:
	rm -rf gen.objdir

output: gen.objdir
