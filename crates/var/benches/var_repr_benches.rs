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

//! Codegen probes for alternate `Var` scalar representation shapes.
//!
//! The timings are secondary. The useful output is release assembly for the small loops below.

use micromeasure::{
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, NoContext, Throughput,
    benchmark_main, black_box,
};
use std::time::Duration;

const TAG_INT: u8 = 3;
const TAG_STR: u8 = 0x81;

#[repr(C)]
#[derive(Clone, Copy)]
struct CurrentRepr {
    tag: u8,
    meta: [u8; 7],
    data: u64,
}

impl CurrentRepr {
    #[inline(always)]
    fn int(value: i64) -> Self {
        Self {
            tag: TAG_INT,
            meta: [0; 7],
            data: value as u64,
        }
    }

    #[inline(always)]
    fn as_int(&self) -> Option<i64> {
        if self.tag == TAG_INT {
            Some(self.data as i64)
        } else {
            None
        }
    }
}

#[repr(C)]
struct CurrentDropRepr {
    tag: u8,
    meta: [u8; 7],
    data: u64,
}

impl CurrentDropRepr {
    #[inline(always)]
    fn int(value: i64) -> Self {
        Self {
            tag: TAG_INT,
            meta: [0; 7],
            data: value as u64,
        }
    }
}

impl Drop for CurrentDropRepr {
    #[inline]
    fn drop(&mut self) {
        if self.tag & 0x80 != 0 {
            black_box(self.data);
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct HeaderRepr {
    header: u64,
    data: u64,
}

impl HeaderRepr {
    #[inline(always)]
    fn int(value: i64) -> Self {
        Self {
            header: TAG_INT as u64,
            data: value as u64,
        }
    }

    #[inline(always)]
    fn str_with_meta(data: u64, len: u16, hint: u8) -> Self {
        let header = TAG_STR as u64 | ((len as u64) << 8) | ((hint as u64) << 56);
        Self { header, data }
    }

    #[inline(always)]
    fn tag(&self) -> u8 {
        self.header as u8
    }

    #[inline(always)]
    fn as_int(&self) -> Option<i64> {
        if self.tag() == TAG_INT {
            Some(self.data as i64)
        } else {
            None
        }
    }
}

#[repr(C)]
struct HeaderDropRepr {
    header: u64,
    data: u64,
}

impl HeaderDropRepr {
    #[inline(always)]
    fn int(value: i64) -> Self {
        Self {
            header: TAG_INT as u64,
            data: value as u64,
        }
    }
}

impl Drop for HeaderDropRepr {
    #[inline]
    fn drop(&mut self) {
        if self.header & 0x80 != 0 {
            black_box(self.data);
        }
    }
}

struct ReprContext {
    current: CurrentRepr,
    header: HeaderRepr,
}

impl BenchContext for ReprContext {
    fn prepare(_num_chunks: usize) -> Self {
        Self {
            current: CurrentRepr::int(42),
            header: HeaderRepr::int(42),
        }
    }
}

fn current_construct_int(_ctx: &mut NoContext, chunk_size: usize, _chunk_num: usize) {
    for i in 0..chunk_size {
        black_box(CurrentRepr::int(i as i64));
    }
}

fn header_construct_int(_ctx: &mut NoContext, chunk_size: usize, _chunk_num: usize) {
    for i in 0..chunk_size {
        black_box(HeaderRepr::int(i as i64));
    }
}

fn header_construct_str_meta(_ctx: &mut NoContext, chunk_size: usize, _chunk_num: usize) {
    for i in 0..chunk_size {
        black_box(HeaderRepr::str_with_meta(
            i as u64,
            (i & 0xffff) as u16,
            (i & 7) as u8,
        ));
    }
}

fn current_drop_int(_ctx: &mut NoContext, chunk_size: usize, _chunk_num: usize) {
    for i in 0..chunk_size {
        black_box(CurrentDropRepr::int(i as i64));
    }
}

fn header_drop_int(_ctx: &mut NoContext, chunk_size: usize, _chunk_num: usize) {
    for i in 0..chunk_size {
        black_box(HeaderDropRepr::int(i as i64));
    }
}

fn current_as_int(ctx: &mut ReprContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(ctx.current.as_int());
    }
}

fn header_as_int(ctx: &mut ReprContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(ctx.header.as_int());
    }
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some("all or any representation probe substring".to_string()),
        runtime: BenchmarkRuntimeOptions {
            warm_up_duration: Duration::from_millis(100),
            benchmark_duration: Duration::from_millis(250),
            min_samples: 4,
            max_samples: 8,
        },
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        runner.group::<NoContext>("Var Representation Construction", |g| {
            let g = g.throughput(Throughput::per_operation(1, "reprs"));
            g.bench("current_construct_int", current_construct_int);
            g.bench("header_construct_int", header_construct_int);
            g.bench("header_construct_str_meta", header_construct_str_meta);
            g.bench("current_drop_int", current_drop_int);
            g.bench("header_drop_int", header_drop_int);
        });

        runner.group::<ReprContext>("Var Representation Accessors", |g| {
            let g = g.throughput(Throughput::per_operation(1, "reprs"));
            g.bench("current_as_int", current_as_int);
            g.bench("header_as_int", header_as_int);
        });
    }
);
