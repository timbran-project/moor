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
use moor_compiler::{CompileOptions, ObjFileContext, compile_object_definitions};

struct ObjDefContext {
    options: CompileOptions,
    small: String,
    medium: String,
    large: String,
}

impl ObjDefContext {
    fn small_objdef() -> &'static str {
        r#"
object #1
    parent: #1
    name: "Small Object"
    location: #2
    wizard: false
    programmer: false
    player: false
    fertile: true
    readable: true

    property description (owner: #1, flags: "rc") = "small";
    override description = "small updated";

    verb look_self (this none this) owner: #1 flags: "rxd"
        return this;
    endverb
endobject
"#
    }

    fn medium_objdef() -> String {
        let mut src = String::with_capacity(64 * 1024);
        src.push_str("define ROOT = #1;\n");
        src.push_str("define OWNER = #2;\n\n");

        for i in 1..=64 {
            src.push_str("object #");
            src.push_str(&i.to_string());
            src.push('\n');
            src.push_str("    parent: ROOT\n");
            src.push_str("    name: \"Medium ");
            src.push_str(&i.to_string());
            src.push_str("\"\n");
            src.push_str("    location: OWNER\n");
            src.push_str("    wizard: false\n");
            src.push_str("    programmer: false\n");
            src.push_str("    player: false\n");
            src.push_str("    fertile: true\n");
            src.push_str("    readable: true\n\n");

            src.push_str("    property p");
            src.push_str(&i.to_string());
            src.push_str(" (owner: OWNER, flags: \"rc\") = ");
            src.push_str(&i.to_string());
            src.push_str(";\n");
            src.push_str("    override p");
            src.push_str(&i.to_string());
            src.push_str(" = ");
            src.push_str(&(i + 1).to_string());
            src.push_str(";\n\n");

            src.push_str("    verb v");
            src.push_str(&i.to_string());
            src.push_str(" (this none this) owner: OWNER flags: \"rxd\"\n");
            src.push_str("        x = ");
            src.push_str(&(i % 9).to_string());
            src.push_str(";\n");
            src.push_str("        while (x < 50)\n");
            src.push_str("            x = x + 1;\n");
            src.push_str("        endwhile\n");
            src.push_str("        return x;\n");
            src.push_str("    endverb\n");
            src.push_str("endobject\n\n");
        }

        src
    }

    fn large_objdef() -> String {
        let mut src = String::with_capacity(512 * 1024);
        src.push_str("define ROOT = #1;\n");
        src.push_str("define OWNER = #2;\n");
        src.push_str("define PLACE = #3;\n\n");

        for i in 1..=200 {
            src.push_str("object #");
            src.push_str(&i.to_string());
            src.push('\n');
            src.push_str("    parent: ROOT\n");
            src.push_str("    name: \"Large ");
            src.push_str(&i.to_string());
            src.push_str("\"\n");
            src.push_str("    location: PLACE\n");
            src.push_str("    wizard: false\n");
            src.push_str("    programmer: false\n");
            src.push_str("    player: false\n");
            src.push_str("    fertile: true\n");
            src.push_str("    readable: true\n\n");

            for p in 0..3 {
                src.push_str("    property p");
                src.push_str(&i.to_string());
                src.push('_');
                src.push_str(&p.to_string());
                src.push_str(" (owner: OWNER, flags: \"rc\") = ");
                src.push_str(&(i + p).to_string());
                src.push_str(";\n");
            }

            for p in 0..3 {
                src.push_str("    override p");
                src.push_str(&i.to_string());
                src.push('_');
                src.push_str(&p.to_string());
                src.push_str(" = ");
                src.push_str(&(i + p + 10).to_string());
                src.push_str(";\n");
            }
            src.push('\n');

            for v in 0..2 {
                src.push_str("    verb v");
                src.push_str(&i.to_string());
                src.push('_');
                src.push_str(&v.to_string());
                src.push_str(" (this none this) owner: OWNER flags: \"rxd\"\n");
                src.push_str("        sum = 0;\n");
                src.push_str("        for n in [1..40]\n");
                src.push_str("            if (n % 2 == 0)\n");
                src.push_str("                sum = sum + n;\n");
                src.push_str("            else\n");
                src.push_str("                sum = sum + 1;\n");
                src.push_str("            endif\n");
                src.push_str("        endfor\n");
                src.push_str("        return sum;\n");
                src.push_str("    endverb\n\n");
            }
            src.push_str("endobject\n\n");
        }

        src
    }
}

impl BenchContext for ObjDefContext {
    fn prepare(_num_chunks: usize) -> Self {
        Self {
            options: CompileOptions::default(),
            small: Self::small_objdef().to_string(),
            medium: Self::medium_objdef(),
            large: Self::large_objdef(),
        }
    }

    fn chunk_size() -> Option<usize> {
        Some(1)
    }
}

fn compile_small(ctx: &mut ObjDefContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        let mut context = ObjFileContext::new();
        black_box(compile_object_definitions(
            black_box(ctx.small.as_str()),
            &ctx.options,
            &mut context,
        ))
        .expect("small objdef should compile");
    }
}

fn compile_medium(ctx: &mut ObjDefContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        let mut context = ObjFileContext::new();
        black_box(compile_object_definitions(
            black_box(ctx.medium.as_str()),
            &ctx.options,
            &mut context,
        ))
        .expect("medium objdef should compile");
    }
}

fn compile_large(ctx: &mut ObjDefContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        let mut context = ObjFileContext::new();
        black_box(compile_object_definitions(
            black_box(ctx.large.as_str()),
            &ctx.options,
            &mut context,
        ))
        .expect("large objdef should compile");
    }
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some("all, small, medium, large, or any benchmark name substring".to_string()),
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        let small_bytes = ObjDefContext::small_objdef().len() as u64;
        let medium_bytes = ObjDefContext::medium_objdef().len() as u64;
        let large_bytes = ObjDefContext::large_objdef().len() as u64;

        runner.group::<ObjDefContext>("Compiler Object Definition Benchmarks", |g| {
            g.throughput(Throughput::per_operation(small_bytes, "bytes"))
                .bench("compile_small", compile_small);
            g.throughput(Throughput::per_operation(medium_bytes, "bytes"))
                .bench("compile_medium", compile_medium);
            g.throughput(Throughput::per_operation(large_bytes, "bytes"))
                .bench("compile_large", compile_large);
        });
    }
);
