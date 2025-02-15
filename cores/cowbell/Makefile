# Runs moorc from the latest docker release, mapping local working directory
MOORC = docker run -v .:/work -i ghcr.io/rdaum/moor:release ./moorc \
	--use-boolean-returns true \
	--use-symbols-in-builtins true

# Target to generate an old-style MOO textdump from the compilation of the
# objdef style sources in the local directory. This is the default target,
# and is intended mainly just to do a validation/compilation pass.
gen.moo-textdump: $(wildcard *.moo)
	$(MOORC) --src-objdef-dir /work --out-textdump /work/$@

# Target to generate a new objdef dump from the compilation of the local
# directory.
gen.objdir: $(wildcard *.moo)
	$(MOORC) --src-objdef-dir /work --out-objdef-dir /work/gen.objdir

# Builds a new objdef dump and then copies over the local working sources.
# WARNING: this is destructive to local changes you might have -- it *will*
# overwrite them -- and is meant  mainly as the last step before performing a
# git commit.
rebuild: gen.objdir
	cp gen.objdir/*.moo .

clean:
	rm -f gen.moo-textdump

output: gen.moo-textdump

