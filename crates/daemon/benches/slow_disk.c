// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

// A slow disk, for benchmarks: preloaded, it makes syncing a regular file take
// SLOW_DISK_SYNC_US microseconds longer (8000 by default, about a spinning
// disk's seek and rotation), and writing to one SLOW_DISK_WRITE_US longer (0
// by default). Pipes, sockets and terminals are left alone, so logging and IPC
// stay as fast as they were.
//
//   cc -shared -fPIC -O2 -o target/slow_disk.so crates/daemon/benches/slow_disk.c -ldl
//   LD_PRELOAD=$PWD/target/slow_disk.so target/release/deps/connection_registry_benches-...
//
// It needs no privileges, and applies to whatever the process does through
// libc: fjall's journal and table writes and syncs among them.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static long delay_from(const char *name, long fallback) {
    const char *value = getenv(name);
    return value ? atol(value) : fallback;
}

static void pause_for(long micros) {
    if (micros <= 0) {
        return;
    }
    struct timespec wait = {micros / 1000000, (micros % 1000000) * 1000};
    while (nanosleep(&wait, &wait) != 0) {
    }
}

static int is_regular_file(int fd) {
    struct stat st;
    return fstat(fd, &st) == 0 && S_ISREG(st.st_mode);
}

static void before_sync(int fd) {
    static long micros = -1;
    if (micros < 0) {
        micros = delay_from("SLOW_DISK_SYNC_US", 8000);
    }
    if (is_regular_file(fd)) {
        pause_for(micros);
    }
}

static void before_write(int fd) {
    static long micros = -1;
    if (micros < 0) {
        micros = delay_from("SLOW_DISK_WRITE_US", 0);
    }
    if (micros > 0 && is_regular_file(fd)) {
        pause_for(micros);
    }
}

int fsync(int fd) {
    static int (*real)(int);
    if (!real) {
        real = dlsym(RTLD_NEXT, "fsync");
    }
    before_sync(fd);
    return real(fd);
}

int fdatasync(int fd) {
    static int (*real)(int);
    if (!real) {
        real = dlsym(RTLD_NEXT, "fdatasync");
    }
    before_sync(fd);
    return real(fd);
}

ssize_t write(int fd, const void *buf, size_t count) {
    static ssize_t (*real)(int, const void *, size_t);
    if (!real) {
        real = dlsym(RTLD_NEXT, "write");
    }
    before_write(fd);
    return real(fd, buf, count);
}

ssize_t writev(int fd, const struct iovec *iov, int iovcnt) {
    static ssize_t (*real)(int, const struct iovec *, int);
    if (!real) {
        real = dlsym(RTLD_NEXT, "writev");
    }
    before_write(fd);
    return real(fd, iov, iovcnt);
}

ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset) {
    static ssize_t (*real)(int, const void *, size_t, off_t);
    if (!real) {
        real = dlsym(RTLD_NEXT, "pwrite");
    }
    before_write(fd);
    return real(fd, buf, count, offset);
}

ssize_t pwrite64(int fd, const void *buf, size_t count, off_t offset) {
    static ssize_t (*real)(int, const void *, size_t, off_t);
    if (!real) {
        real = dlsym(RTLD_NEXT, "pwrite64");
    }
    before_write(fd);
    return real(fd, buf, count, offset);
}
