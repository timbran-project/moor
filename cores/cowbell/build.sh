#!/bin/sh

docker run -v .:/src -i ghcr.io/rdaum/moor:release ./moorc --src-objdef-dir /src
