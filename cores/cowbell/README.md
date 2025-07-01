## mooR cowbell

This is a work-in-progress from-scratch "core" database for [mooR](http://github.com/rdaum/moor).

Goal is to build the foundation for a rich, social environment in the spirit of classic MOOs and
TinyMU* systems, but future-facing.

- Start with the web and rich content as first-class elements.
- Use new language features like lexical scopes / blocks, symbols, booleans, list comprehensions,
  and maps.
- Core is written using the objdef format, so can be properly managed and authored in revision
  control tools. While changes can be made in-MOO, they are meant to be merged back into the
  repository as the canonical version.

(Note: While some utility code might get ported from Lambda or JHCore the intent is start from
scratch to take advantage of `mooR`'s more advanced features. Wholesale porting of generic objects
it not expected / desired)

## Development

To compile / validate your changes use the provided `Makefile`

- `make` will use the latest mooR release (via docker) to compiler / import "*.moo" into a local
  generated old-style textdump file, for the purpose of validation
- `make clean` will destroy said file
- `make gen.objdir` will build a new objdef dir from the local changes.
- `make rebuild` will build a new objdef dir with your local changes and then (WARNING) _overwrite_
  your local changes. Think of this is as a formatting step (for prior to commit, etc)

To run a moor instance with the provided core database, first make sure you don't have any old
database files lying around locally, and then run

`docker compose up`

## Contribution

Pull requests accepted.
