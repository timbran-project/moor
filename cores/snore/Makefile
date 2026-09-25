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

.DEFAULT_GOAL := build
.DELETE_ON_ERROR:

CARGO ?= cargo
MOORC ?= $(CARGO) run -p moorc --

# Keep build output in the workspace target directory regardless of where make runs.
export CARGO_TARGET_DIR ?= ../../target

# Method-harness principals. The wizard and programmer are core characters; the
# non-programmer player is the fixture at #101 in the test overlay.
TEST_WIZARD ?= 2
TEST_PROGRAMMER ?= 36
TEST_PLAYER ?= 101
TEST_HARNESS ?= 100
TEST_TASK_PLAYER ?=
TEST_FILTER ?=
TEST_TIMEOUT ?= 30

TESTSRC := gen.testsrc
TEST_LOG := gen.test.log
FIXTURES := tests/fixtures

FEATURES = --bool-type true \
           --use-boolean-returns true \
           --symbol-type true \
           --use-symbols-in-builtins true \
           --custom-errors true \
           --use-uuobjids true \
           --flyweight-type false \
           --rich-notify false

# Local launcher: all state stays under RUN_DIR inside this core directory, so
# it cannot touch the databases of the other cores. The daemon receives the same
# feature configuration the sources were built with.
RUN_DIR ?= gen.run
RUN_DATA ?= $(RUN_DIR)/data
RUN_CONFIG ?= $(RUN_DIR)/config
RUN_HOST_DATA ?= $(RUN_DIR)/telnet-host
DAEMON ?= $(CARGO) run -p moor-daemon --
TELNET_HOST ?= $(CARGO) run -p moor-telnet-host --
RUN_ABS := $(abspath $(RUN_DIR))
RUN_LISTEN = --rpc-listen ipc://$(RUN_ABS)/rpc.sock \
             --events-listen ipc://$(RUN_ABS)/events.sock \
             --workers-response-listen ipc://$(RUN_ABS)/workers-response.sock \
             --workers-request-listen ipc://$(RUN_ABS)/workers-request.sock \
             --enrollment-listen ipc://$(RUN_ABS)/enrollment.sock

.PHONY: check audit-style check-style build rebuild reformat gen.objdir check-sources test test-headless test-session test-harness test-wire test-extraction test-collection-roundtrip measure roundtrip run run-telnet run-clean clean help

# These targets share the test overlay and log. Do not run them concurrently.
.NOTPARALLEL:

check:
	$(MAKE) check-style
	$(MAKE) test
	$(MAKE) test-headless
	$(MAKE) test-session
	$(MAKE) test-harness
	$(MAKE) roundtrip
	$(MAKE) test-collection-roundtrip

# Always import the complete tree, including nested sources and removed files.
build: gen.objdir

# Normalize working sources only after the export survives reimport unchanged.
# Export regenerates objdef formatting and does not preserve source comments.
reformat: roundtrip
	cp -r gen.objdir/. src/

rebuild: reformat

gen.objdir: check-sources
	rm -rf gen.objdir gen.objdir.in-progress
	$(MOORC) $(FEATURES) --src-objdef-dir src --out-objdef-dir gen.objdir
	@test -d gen.objdir || { echo "FAIL: compiler did not produce an export" >&2; exit 1; }

check-sources:
	@test -n "$$(find src -type f -name '*.moo' -print -quit)" || { \
		echo "No core sources yet. Add objdef files under src/ before building." >&2; \
		exit 1; \
	}

# Test overlay: shipped core plus fixtures. Fixtures never enter src/.
gen.testsrc: check-sources $(wildcard src/*.moo) $(wildcard $(FIXTURES)/*.moo)
	rm -rf gen.testsrc
	cp -r src gen.testsrc
	cp $(FIXTURES)/*.moo gen.testsrc/
	cat $(FIXTURES)/fixture_constants.moo >> gen.testsrc/constants.moo
	rm -f gen.testsrc/fixture_constants.moo

# Method harness. Fails when discovery finds no test_ entry points.
test: gen.testsrc
	@$(MOORC) $(FEATURES) --src-objdef-dir gen.testsrc \
		--run-tests true --test-wizard $(TEST_WIZARD) \
		--test-programmer $(TEST_PROGRAMMER) --test-player $(TEST_PLAYER) \
		--test-timeout $(TEST_TIMEOUT) \
		$(if $(TEST_TASK_PLAYER),--test-task-player $(TEST_TASK_PLAYER),) \
		$(if $(TEST_FILTER),--test-filter "$(TEST_FILTER)",) \
		> $(TEST_LOG) 2>&1; status=$$?; cat $(TEST_LOG); \
		grep -qE 'Found [1-9][0-9]* tests' $(TEST_LOG) || { \
			echo "FAIL: method suite discovered no tests" >&2; exit 1; }; \
		if grep -qE 'Filtered tests from [0-9]+ to 0' $(TEST_LOG); then \
			echo "FAIL: TEST_FILTER selected no methods" >&2; exit 1; fi; \
		exit $$status

# Headless command scenarios through the scheduler. Fails when none are found.
test-headless: gen.testsrc
	@$(MOORC) $(FEATURES) --src-objdef-dir gen.testsrc \
		--test-wizard $(TEST_WIZARD) --test-programmer $(TEST_PROGRAMMER) \
		--test-player $(TEST_PLAYER) \
		--test-files 'tests/moot/*.moot' \
		> $(TEST_LOG) 2>&1; status=$$?; cat $(TEST_LOG); \
		grep -qE 'Running [1-9][0-9]* integration tests' $(TEST_LOG) || { \
			echo "FAIL: headless suite discovered no scenarios" >&2; exit 1; }; \
		exit $$status

# Mock-session scenarios through the kernel scheduler against the test overlay.
test-session: gen.testsrc
	@$(CARGO) run --manifest-path tools/session-runner/Cargo.toml -- \
		--core-dir gen.testsrc --moot tests/sessions \
		> $(TEST_LOG) 2>&1; s1=$$?; \
	$(CARGO) run --manifest-path tools/session-runner/Cargo.toml -- \
		--core-dir gen.testsrc --moot tests/sessions-game --nonprogrammer 108 \
		>> $(TEST_LOG) 2>&1; s2=$$?; cat $(TEST_LOG); \
	grep -q 'Test definition: tests/sessions/' $(TEST_LOG) || { \
		echo "FAIL: default session suite discovered no scenarios" >&2; exit 1; }; \
	grep -q 'Test definition: tests/sessions-game/' $(TEST_LOG) || { \
		echo "FAIL: game session suite discovered no scenarios" >&2; exit 1; }; \
	[ $$s1 -eq 0 ] && [ $$s2 -eq 0 ] || { echo "FAIL: session scenarios failed" >&2; exit 1; }

# Command exceptions must fail even when the scenario has no output assertions.
test-harness: gen.testsrc
	$(CARGO) test --manifest-path tools/session-runner/Cargo.toml
	$(CARGO) run --manifest-path tools/session-runner/Cargo.toml -- \
		--core-dir gen.testsrc --moot tests/harness/eval_errors.moot
	@$(CARGO) run --manifest-path tools/session-runner/Cargo.toml -- \
		--core-dir gen.testsrc --moot tests/harness/command_exception.moot \
		> gen.harness.log 2>&1; status=$$?; cat gen.harness.log; \
	[ $$status -ne 0 ] && grep -q 'command task aborted:.*harness command exception' gen.harness.log || { \
		echo "FAIL: runner accepted command exception or failed for another reason" >&2; exit 1; }; \
	echo "PASS: runner rejected command exception"

# Wire scenarios through a real daemon, telnet host, and TCP clients.
test-wire: gen.testsrc
	$(CARGO) build -p moor-daemon -p moor-telnet-host
	python3 tests/wire.py --daemon $(CARGO_TARGET_DIR)/debug/moor-daemon \
		--host $(CARGO_TARGET_DIR)/debug/moor-telnet-host --core gen.testsrc

# Destructive extraction checks always import src into disposable databases.
test-extraction:
	$(CARGO) run --manifest-path tools/session-runner/Cargo.toml -- \
		--core-dir src --moot tests/extraction --wizard 2 --programmer 2 --nonprogrammer 2
	$(CARGO) build -p moor-server --bin moor -p moorc --bin moorc
	python3 tests/extraction.py --server $(CARGO_TARGET_DIR)/debug/moor \
		--moorc $(CARGO_TARGET_DIR)/debug/moorc --core src

# Execute a stored captured closure after fixture export and reimport.
test-collection-roundtrip: gen.testsrc
	rm -rf gen.collections.rt gen.collections.rt.in-progress
	$(MOORC) $(FEATURES) --src-objdef-dir gen.testsrc --out-objdef-dir gen.collections.rt
	@test -d gen.collections.rt || { echo "FAIL: compiler did not produce an export" >&2; exit 1; }
	@$(MOORC) $(FEATURES) --src-objdef-dir gen.collections.rt \
		--run-tests true --test-wizard $(TEST_WIZARD) \
		--test-programmer $(TEST_PROGRAMMER) --test-player $(TEST_PLAYER) \
		--test-filter '#$(TEST_HARNESS):test_collection_callbacks' \
		> gen.collections.log 2>&1; status=$$?; cat gen.collections.log; \
		grep -q 'Test #$(TEST_HARNESS):test_collection_callbacks passed' gen.collections.log || { \
			echo "FAIL: captured closure did not pass after reimport" >&2; exit 1; }; \
		exit $$status

# Check source contracts, bindings, and conditional assignments.
audit-style:
	$(CARGO) run --manifest-path tools/style-audit/Cargo.toml -- src

check-style:
	$(CARGO) run --manifest-path tools/style-audit/Cargo.toml -- src --strict

# Storage and interaction measurements.
measure: gen.testsrc
	@$(MOORC) $(FEATURES) --src-objdef-dir gen.testsrc \
		--run-tests true --test-wizard $(TEST_WIZARD) \
		--test-programmer $(TEST_PROGRAMMER) --test-player $(TEST_PLAYER) \
		--test-timeout 120 --test-filter '#$(TEST_HARNESS):test_storage_measurements' \
		> $(TEST_LOG) 2>&1; status=$$?; \
		grep -E 'MEASURE|passed|failed|Error' $(TEST_LOG); [ $$status -eq 0 ] || exit $$status; \
		$(MOORC) $(FEATURES) --src-objdef-dir gen.testsrc \
		--run-tests true --test-wizard $(TEST_WIZARD) \
		--test-programmer $(TEST_PROGRAMMER) --test-player $(TEST_PLAYER) \
		--test-timeout 120 --test-filter '#$(TEST_HARNESS):test_interaction_measurements' \
		> $(TEST_LOG) 2>&1; status=$$?; \
		grep -E 'MEASURE|passed|failed|Error' $(TEST_LOG); exit $$status

# Core identities must survive export and reimport unchanged.
roundtrip: gen.objdir
	rm -rf gen.objdir.rt
	$(MOORC) $(FEATURES) --src-objdef-dir gen.objdir --out-objdef-dir gen.objdir.rt
	diff -r gen.objdir gen.objdir.rt
	@echo "roundtrip: export is stable across reimport"

# Start the core from its own isolated data directory. The first run imports
# gen.objdir and generates the host keypair and enrollment token under RUN_DIR;
# later runs resume the existing database. Paths are absolute so the daemon's
# config-directory defaults cannot leak state into the user's home.
run: gen.objdir
	@mkdir -p $(RUN_ABS)/data $(RUN_ABS)/config
	@if [ ! -d $(RUN_ABS)/data/world.db ]; then \
		echo "Importing gen.objdir into $(RUN_ABS)/data/world.db"; \
		$(DAEMON) $(RUN_ABS)/data --db world.db --import gen.objdir --import-format objdef \
			--generate-keypair \
			--public-key $(RUN_ABS)/config/moor-verifying-key.pem \
			--private-key $(RUN_ABS)/config/moor-signing-key.pem \
			--enrollment-token-file $(RUN_ABS)/config/enrollment-token \
			$(RUN_LISTEN) $(FEATURES); \
	else \
		echo "Resuming $(RUN_ABS)/data/world.db"; \
		$(DAEMON) $(RUN_ABS)/data --db world.db \
			--public-key $(RUN_ABS)/config/moor-verifying-key.pem \
			--private-key $(RUN_ABS)/config/moor-signing-key.pem \
			--enrollment-token-file $(RUN_ABS)/config/enrollment-token \
			$(RUN_LISTEN) $(FEATURES); \
	fi

# Connect a telnet host to a daemon started with `make run` (in another shell).
run-telnet:
	@mkdir -p $(RUN_ABS)/telnet-host
	$(TELNET_HOST) \
		--rpc-address ipc://$(RUN_ABS)/rpc.sock \
		--events-address ipc://$(RUN_ABS)/events.sock \
		--workers-response-address ipc://$(RUN_ABS)/workers-response.sock \
		--workers-request-address ipc://$(RUN_ABS)/workers-request.sock \
		--enrollment-address ipc://$(RUN_ABS)/enrollment.sock \
		--enrollment-token-file $(RUN_ABS)/config/enrollment-token \
		--data-dir $(RUN_ABS)/telnet-host

run-clean:
	rm -rf $(RUN_DIR)

clean:
	rm -rf gen.objdir gen.objdir.in-progress gen.objdir.rt gen.objdir.rt.in-progress gen.testsrc gen.test.log gen.harness.log gen.collections.rt gen.collections.rt.in-progress gen.collections.log

help:
	@printf '%s\n' \
		'make check              Run style, method, command, session, and roundtrip checks in order.' \
		'make                    Import src/ and export normalized objdef to gen.objdir/.' \
		'make reformat           Validate export/reimport and overwrite src/ with normalized objdef.' \
		'make rebuild            Alias for reformat.' \
		'make audit-style        Print parser-backed source findings.' \
		'make check-style        Require explicit locals, initial contracts, and separate conditional assignments.' \
		'make test               Run test_ methods from the core plus tests/fixtures overlay.' \
		'make test-headless      Run .moot command scenarios under tests/moot.' \
		'make test-session       Run mock-session scenarios under tests/sessions.' \
		'make test-harness       Check runner exception handling and builtin map keys.' \
		'make test-wire          Run isolated TCP login and authoring scenarios.' \
		'make test-extraction    Check isolated extraction, restart/resume, and export.' \
		'make test-collection-roundtrip  Execute a saved closure after export/reimport.' \
		'make measure            Run the measurement tests and print MEASURE lines.' \
		'make roundtrip          Export, reimport, and compare objdef for identity stability.' \
		'make run                Start the daemon from isolated state under gen.run/.' \
		'make run-telnet         Connect a telnet host to a running `make run` daemon.' \
		'make run-clean          Remove the launcher state (does not touch src/).' \
		'make clean              Remove generated output.' \
		'MOORC=...               Override the compiler command, including its arguments.' \
		'CARGO="cargo +toolchain" Use a specific cargo toolchain.' \
		'TEST_FILTER=#100:test_x Only run matching test_ verbs.'
