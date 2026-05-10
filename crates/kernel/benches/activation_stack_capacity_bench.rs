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

//! Activation-stack capacity micro-benchmarks.
//!
//! These isolate the allocation/drop cost of the activation stack backing store used by
//! `ExecState::stack`. `MaybeUninit<Activation>` has the same allocation layout as
//! `Activation` without constructing a real activation for each slot.

use std::{
    mem::{MaybeUninit, size_of},
    time::Duration,
};

use micromeasure::{
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, Throughput, benchmark_main,
    black_box,
};
use moor_vm::Activation;

struct ActivationStackCapacityContext;

impl BenchContext for ActivationStackCapacityContext {
    fn prepare(_num_chunks: usize) -> Self {
        Self
    }
}

fn bench_stack_alloc<const CAPACITY: usize>(
    _ctx: &mut ActivationStackCapacityContext,
    chunk_size: usize,
    _chunk_num: usize,
) {
    for _ in 0..chunk_size {
        let stack = Vec::<MaybeUninit<Activation>>::with_capacity(CAPACITY);
        black_box(stack);
    }
}

fn bench_stack_alloc_push_one<const CAPACITY: usize>(
    _ctx: &mut ActivationStackCapacityContext,
    chunk_size: usize,
    _chunk_num: usize,
) {
    for _ in 0..chunk_size {
        let mut stack = Vec::<MaybeUninit<Activation>>::with_capacity(CAPACITY);
        stack.push(MaybeUninit::uninit());
        black_box(stack);
    }
}

fn bench_stack_grow<const START_CAPACITY: usize, const PUSHES: usize>(
    _ctx: &mut ActivationStackCapacityContext,
    chunk_size: usize,
    _chunk_num: usize,
) {
    for _ in 0..chunk_size {
        let mut stack = Vec::<MaybeUninit<Activation>>::with_capacity(START_CAPACITY);
        for _ in 0..PUSHES {
            stack.push(MaybeUninit::uninit());
        }
        black_box(stack);
    }
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some(
            "all, alloc, push, grow, or any activation_stack_capacity benchmark name substring"
                .to_string(),
        ),
        runtime: BenchmarkRuntimeOptions {
            warm_up_duration: Duration::from_millis(250),
            benchmark_duration: Duration::from_secs(1),
            min_samples: 8,
            max_samples: 24,
        },
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        eprintln!(
            "Activation stack element size: {} bytes",
            size_of::<Activation>()
        );

        runner.group::<ActivationStackCapacityContext>("activation_stack_capacity_alloc", |g| {
            let g = g.throughput(Throughput::per_operation(1, "vectors"));
            g.bench("activation_stack_capacity_alloc_0", bench_stack_alloc::<0>);
            g.bench("activation_stack_capacity_alloc_1", bench_stack_alloc::<1>);
            g.bench("activation_stack_capacity_alloc_4", bench_stack_alloc::<4>);
            g.bench("activation_stack_capacity_alloc_8", bench_stack_alloc::<8>);
            g.bench(
                "activation_stack_capacity_alloc_16",
                bench_stack_alloc::<16>,
            );
            g.bench(
                "activation_stack_capacity_alloc_32",
                bench_stack_alloc::<32>,
            );
            g.bench(
                "activation_stack_capacity_alloc_64",
                bench_stack_alloc::<64>,
            );
        });

        runner.group::<ActivationStackCapacityContext>("activation_stack_capacity_push", |g| {
            let g = g.throughput(Throughput::per_operation(1, "vectors"));
            g.bench(
                "activation_stack_capacity_push_0",
                bench_stack_alloc_push_one::<0>,
            );
            g.bench(
                "activation_stack_capacity_push_1",
                bench_stack_alloc_push_one::<1>,
            );
            g.bench(
                "activation_stack_capacity_push_4",
                bench_stack_alloc_push_one::<4>,
            );
            g.bench(
                "activation_stack_capacity_push_8",
                bench_stack_alloc_push_one::<8>,
            );
            g.bench(
                "activation_stack_capacity_push_16",
                bench_stack_alloc_push_one::<16>,
            );
            g.bench(
                "activation_stack_capacity_push_32",
                bench_stack_alloc_push_one::<32>,
            );
            g.bench(
                "activation_stack_capacity_push_64",
                bench_stack_alloc_push_one::<64>,
            );
        });

        runner.group::<ActivationStackCapacityContext>("activation_stack_capacity_grow", |g| {
            let g = g.throughput(Throughput::per_operation(1, "vectors"));
            g.bench(
                "activation_stack_capacity_grow_1_to_2",
                bench_stack_grow::<1, 2>,
            );
            g.bench(
                "activation_stack_capacity_grow_4_to_5",
                bench_stack_grow::<4, 5>,
            );
            g.bench(
                "activation_stack_capacity_grow_8_to_9",
                bench_stack_grow::<8, 9>,
            );
            g.bench(
                "activation_stack_capacity_grow_16_to_17",
                bench_stack_grow::<16, 17>,
            );
            g.bench(
                "activation_stack_capacity_grow_32_to_33",
                bench_stack_grow::<32, 33>,
            );
            g.bench("activation_stack_capacity_fit_8", bench_stack_grow::<8, 8>);
            g.bench(
                "activation_stack_capacity_fit_16",
                bench_stack_grow::<16, 16>,
            );
            g.bench(
                "activation_stack_capacity_fit_32",
                bench_stack_grow::<32, 32>,
            );
        });
    }
);
