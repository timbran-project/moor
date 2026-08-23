# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
# software: you can redistribute it and/or modify it under the terms of the GNU
# Affero General Public License as published by the Free Software Foundation,
# version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        binutils \
        bpftrace \
        linux-tools-generic \
        procps \
        python3 \
        tar && \
    perf_path=$(find /usr/lib/linux-tools -name perf -print -quit) && \
    test -n "${perf_path}" && \
    ln -s "${perf_path}" /usr/local/bin/perf && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /moor
COPY tools/perf/ /moor/tools/perf/
COPY crates/common/src/builtins.rs /moor/crates/common/src/builtins.rs
