# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

.DEFAULT_GOAL := gen.objdir
export CARGO_TARGET_DIR ?= $(abspath ../../target)

# MOORC binary selection via environment variable MOORC_TYPE
# Options: cargo (default), direct, docker
MOORC_TYPE ?= cargo
HEADLESS_FILTERS ?= 90104 90000 90001 90002 90003 90004 90005 90006 90007 90010 90011 90012 90013 90014 90015
HEADLESS_PLAYER_FILTERS ?= 90008:test_headless_builder_commands_use_stored_grants 90008:test_headless_builder_commands_missing_grants_deny_cleanly 90008:test_headless_builder_message_commands_dispatch_as_player 90014:test_inspection_transfer_reachability 90014:test_inspection_transfers_recheck_after_policy_yield
HEADLESS_WIZARD_FILTERS ?= 90008:test_headless_builder_commands_wizard_builds_without_grants
HEADLESS_TASK_PLAYER ?= 90102
HEADLESS_TIMEOUT ?= 10
TEST_SRC_DIRECTORY ?= .runtime-test-src
HEADLESS_SRC_DIRECTORY ?= .runtime-headless-src
HEADLESS_SRC_STAMP = $(HEADLESS_SRC_DIRECTORY)/.prepared
TEST_WIZARD ?= 90100
TEST_PROGRAMMER ?= 90101
TEST_PLAYER ?= 90102
STYLE_CONVERTED_UNITS = $(shell cat tests/style/converted.txt)
TEST_FILTER ?=
CARGO ?= cargo
.NOTPARALLEL:
.DELETE_ON_ERROR:
HASH := \#
HEADLESS_FILTER_IDS = $(patsubst $(HASH)%,%,$(HEADLESS_FILTERS))
HEADLESS_WIZARD_FILTER_IDS = $(patsubst $(HASH)%,%,$(HEADLESS_WIZARD_FILTERS))
HEADLESS_PLAYER_FILTER_IDS = $(patsubst $(HASH)%,%,$(HEADLESS_PLAYER_FILTERS))

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
MOORC = gdb --batch --ex "handle SIGUSR1 nostop noprint pass" --ex run --ex bt --ex quit --args $(CARGO) run -p moorc -- \
	$(OPTIONS)
else
MOORC = $(CARGO) run -p moorc -- $(OPTIONS)
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

.PHONY: test-wire test-build-inventory runtime-test-src runtime-session test-harness check check-style roundtrip rebuild test runtime-headless runtime-headless-src clean FORCE

check:
	$(MAKE) check-style
	$(MAKE) test
	$(MAKE) runtime-headless
	$(MAKE) runtime-session
	$(MAKE) test-harness
	$(MAKE) roundtrip
	$(MAKE) test-wire
	$(MAKE) test-build-inventory

check-style:
	$(CARGO) run --manifest-path ../snore/tools/style-audit/Cargo.toml -- src --baseline tests/style/baseline.tsv
	$(CARGO) run --manifest-path ../snore/tools/style-audit/Cargo.toml -- src --strict $(foreach unit,$(STYLE_CONVERTED_UNITS),--check $(unit))
	bash tests/style/check-audit.sh $(CARGO_TARGET_DIR)/debug/snore-style-audit

FORCE:

roundtrip: gen.objdir
	rm -rf gen.objdir.rt gen.objdir.rt.in-progress
	$(MOORC) --src-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir.rt
	@test -n "$$(find gen.objdir.rt -name '*.moo' -print -quit)" || { echo "FAIL: reimport export is empty" >&2; exit 1; }
	diff -r gen.objdir gen.objdir.rt

# Target to generate a new objdef dump from the compilation of the local
# directory. This is the default validation/compilation target.
gen.objdir: FORCE
	rm -rf gen.objdir gen.objdir.in-progress
	$(MOORC) --src-objdef-dir $(SRC_DIRECTORY) --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir
	@test -n "$$(find gen.objdir -name '*.moo' -print -quit)" || { echo "FAIL: export is empty" >&2; exit 1; }
	@! grep -qE '= #(900[0-9]+|901[0-9]+);' gen.objdir/constants.moo || { echo "FAIL: test fixtures entered shipped export" >&2; exit 1; }

# Builds a new objdef dump and then copies over the local working sources.
# WARNING: this is destructive to local changes you might have -- it *will*
# overwrite them -- and is meant  mainly as the last step before performing a
# git commit.
rebuild: roundtrip
	cp -r gen.objdir/* ./src/

test: runtime-test-src
	python3 tests/baseline/checked_methods.py $(MOORC) --src-objdef-dir $(TEST_SRC_DIRECTORY) --run-tests true \
		--test-wizard=$(TEST_WIZARD) --test-programmer=$(TEST_PROGRAMMER) --test-player=$(TEST_PLAYER) \
		$(if $(TEST_FILTER),--test-filter "$(TEST_FILTER)",) --test-timeout $(HEADLESS_TIMEOUT)

runtime-test-src: FORCE
	rm -rf $(TEST_SRC_DIRECTORY)
	mkdir -p $(TEST_SRC_DIRECTORY)
	rsync -a src/ $(TEST_SRC_DIRECTORY)/
	rsync -a tests/baseline/fixtures/ $(TEST_SRC_DIRECTORY)/
	cat tests/baseline/fixtures/baseline_constants.moo >> $(TEST_SRC_DIRECTORY)/constants.moo
	rm -f $(TEST_SRC_DIRECTORY)/baseline_constants.moo

$(HEADLESS_SRC_STAMP): runtime-test-src
	rm -rf $(HEADLESS_SRC_DIRECTORY)
	cp -r $(TEST_SRC_DIRECTORY) $(HEADLESS_SRC_DIRECTORY)
	rsync -a tests/headless/ $(HEADLESS_SRC_DIRECTORY)/
	cat tests/headless/headless_constants.moo >> $(HEADLESS_SRC_DIRECTORY)/constants.moo
	rm -f $(HEADLESS_SRC_DIRECTORY)/headless_constants.moo
	touch $(HEADLESS_SRC_STAMP)

runtime-headless-src: $(HEADLESS_SRC_STAMP)

runtime-headless: runtime-headless-src
	@test -n "$(strip $(HEADLESS_FILTER_IDS) $(HEADLESS_PLAYER_FILTER_IDS) $(HEADLESS_WIZARD_FILTER_IDS))" || { echo "FAIL: no headless filters selected" >&2; exit 1; }
	set -e; for filter in $(HEADLESS_FILTER_IDS); do \
		python3 tests/baseline/checked_methods.py $(MOORC) --src-objdef-dir $(HEADLESS_SRC_DIRECTORY) \
		--test-wizard=$(TEST_WIZARD) --test-programmer=$(TEST_PROGRAMMER) --test-player=$(TEST_PLAYER) --run-tests true \
		--test-filter "#$$filter" --test-timeout $(HEADLESS_TIMEOUT); \
	done
	set -e; for filter in $(HEADLESS_PLAYER_FILTER_IDS); do \
		python3 tests/baseline/checked_methods.py $(MOORC) --src-objdef-dir $(HEADLESS_SRC_DIRECTORY) \
		--test-wizard=$(TEST_WIZARD) --test-programmer=$(TEST_PROGRAMMER) --test-player=$(TEST_PLAYER) --test-task-player=$(HEADLESS_TASK_PLAYER) --run-tests true \
		--test-filter "#$$filter" --test-timeout $(HEADLESS_TIMEOUT); \
	done

	set -e; for filter in $(HEADLESS_WIZARD_FILTER_IDS); do \
		python3 tests/baseline/checked_methods.py $(MOORC) --src-objdef-dir $(HEADLESS_SRC_DIRECTORY) \
		--test-wizard=$(TEST_WIZARD) --test-programmer=$(TEST_PROGRAMMER) --test-player=$(TEST_PLAYER) --test-task-player=$(TEST_WIZARD) --run-tests true \
		--test-filter "#$$filter" --test-timeout $(HEADLESS_TIMEOUT); \
	done

clean:
	rm -rf gen.objdir gen.objdir.in-progress gen.objdir.rt gen.objdir.rt.in-progress
	rm -rf $(HEADLESS_SRC_DIRECTORY) $(TEST_SRC_DIRECTORY)
	rm -f gen.empty.log gen.exception.log gen.event-control.log

runtime-session: runtime-headless-src
	$(CARGO) run --manifest-path ../snore/tools/session-runner/Cargo.toml -- --cowbell \
		--core-dir $(HEADLESS_SRC_DIRECTORY) --moot tests/baseline/sessions \
		--wizard $(TEST_WIZARD) --programmer $(TEST_PROGRAMMER) --nonprogrammer $(TEST_PLAYER)

test-harness: runtime-headless-src
	$(CARGO) test --manifest-path ../snore/tools/session-runner/Cargo.toml
	@python3 tests/baseline/checked_methods.py $(MOORC) --src-objdef-dir $(HEADLESS_SRC_DIRECTORY) --run-tests true \
		--test-wizard=$(TEST_WIZARD) --test-filter '#999999' > gen.empty.log 2>&1; status=$$?; \
	cat gen.empty.log; test $$status -ne 0 && grep -q 'FAIL: filter selected no tests' gen.empty.log

	@$(CARGO) run --manifest-path ../snore/tools/session-runner/Cargo.toml -- --cowbell \
		--core-dir $(HEADLESS_SRC_DIRECTORY) --moot tests/baseline/negative/command_exception.moot \
		--wizard $(TEST_WIZARD) --programmer $(TEST_PROGRAMMER) --nonprogrammer $(TEST_PLAYER) \
		> gen.exception.log 2>&1; status=$$?; cat gen.exception.log; \
	test $$status -ne 0 && grep -q 'caught command exception for connection' gen.exception.log

	@set -e; for scenario in wrong_type wrong_audience wrong_recipient; do \
		set +e; $(CARGO) run --manifest-path ../snore/tools/session-runner/Cargo.toml -- --cowbell \
			--core-dir $(HEADLESS_SRC_DIRECTORY) --moot tests/baseline/negative/$$scenario.moot \
			--wizard $(TEST_WIZARD) --programmer $(TEST_PROGRAMMER) --nonprogrammer $(TEST_PLAYER) \
			> gen.event-control.log 2>&1; status=$$?; set -e; cat gen.event-control.log; \
		test $$status -ne 0; grep -qE 'event contract failed|no committed event for recipient' gen.event-control.log; \
	done

	@$(CARGO) run --manifest-path ../snore/tools/session-runner/Cargo.toml -- --cowbell \
		--core-dir $(HEADLESS_SRC_DIRECTORY) --moot tests/baseline/negative/empty.moot \
		--wizard $(TEST_WIZARD) --programmer $(TEST_PROGRAMMER) --nonprogrammer $(TEST_PLAYER) \
		> gen.event-control.log 2>&1; status=$$?; cat gen.event-control.log; \
	test $$status -ne 0 && grep -q 'scenario contains no command or eval steps' gen.event-control.log

test-build-inventory:
	python3 tests/baseline/check_inventory.py $(MOORC)

# Verify actual telnet connections and persistent native schedules after restart.
test-wire:
	CARGO_TARGET_DIR=$(abspath ../../target) $(CARGO) build --manifest-path ../../Cargo.toml -p moor-server --bin moor
	python3 -m unittest discover -s tests -p test_wire.py
	python3 tests/wire.py --server ../../target/debug/moor --core-dir src
