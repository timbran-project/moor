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

use micromeasure::{BenchContext, BenchmarkMainOptions, Throughput, benchmark_main, black_box};
use moor_compiler::{CompileOptions, compile};

struct CompileContext {
    options: CompileOptions,
    tiny: String,
    medium: String,
    large: String,
}

impl CompileContext {
    fn tiny_program() -> &'static str {
        "return 1 + 2 * 3;"
    }

    fn medium_program() -> &'static str {
        r#"
total = 0;
for i in [1..100]
    if (i % 2 == 0)
        total = total + i;
    elseif (i % 3 == 0)
        total = total + (i * 2);
    else
        total = total + 1;
    endif
endfor
return total;
"#
    }

    fn large_program() -> String {
        let mut src = String::with_capacity(128 * 1024);
        src.push_str("total = 0;\n");
        for i in 0..3000 {
            src.push_str("if (");
            src.push_str(&(i % 17).to_string());
            src.push_str(" < 9)\n");
            src.push_str("  total = total + ");
            src.push_str(&(i % 11).to_string());
            src.push_str(";\n");
            src.push_str("else\n");
            src.push_str("  total = total + ");
            src.push_str(&(i % 7).to_string());
            src.push_str(";\n");
            src.push_str("endif\n");
        }
        src.push_str("return total;\n");
        src
    }
}

impl BenchContext for CompileContext {
    fn prepare(_num_chunks: usize) -> Self {
        Self {
            options: CompileOptions::default(),
            tiny: Self::tiny_program().to_string(),
            medium: Self::medium_program().to_string(),
            large: Self::large_program(),
        }
    }

    fn chunk_size() -> Option<usize> {
        Some(1)
    }
}

fn compile_tiny(ctx: &mut CompileContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(compile(black_box(ctx.tiny.as_str()), ctx.options.clone()))
            .expect("tiny benchmark source should compile");
    }
}

fn compile_medium(ctx: &mut CompileContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(compile(black_box(ctx.medium.as_str()), ctx.options.clone()))
            .expect("medium benchmark source should compile");
    }
}

fn compile_large(ctx: &mut CompileContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(compile(black_box(ctx.large.as_str()), ctx.options.clone()))
            .expect("large benchmark source should compile");
    }
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some(
            "all, tiny, medium, large, or any benchmark name substring".to_string(),
        ),
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        let tiny_bytes = CompileContext::tiny_program().len() as u64;
        let medium_bytes = CompileContext::medium_program().len() as u64;
        let large_bytes = CompileContext::large_program().len() as u64;

        runner.group::<CompileContext>("Compiler Compile Benchmarks", |g| {
            g.throughput(Throughput::per_operation(tiny_bytes, "bytes"))
                .bench("compile_tiny", compile_tiny);
            g.throughput(Throughput::per_operation(medium_bytes, "bytes"))
                .bench("compile_medium", compile_medium);
            g.throughput(Throughput::per_operation(large_bytes, "bytes"))
                .bench("compile_large", compile_large);
        });
    }
);
