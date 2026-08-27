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

use micromeasure::{
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, Throughput, benchmark_main,
    black_box,
};
use moor_schema::convert::{encode_db_var, var_to_db_flatbuffer};
use moor_var::{Var, v_list, v_string};
use planus::Builder;
use std::time::Duration;

const HISTORY_ENTRY_COUNT: usize = 1_024;
const HISTORY_ENTRY_BYTES: usize = 2_048;

struct LargeStringHistory(Var);

impl BenchContext for LargeStringHistory {
    fn prepare(_num_chunks: usize) -> Self {
        let entries = (0..HISTORY_ENTRY_COUNT)
            .map(|index| {
                let prefix = format!("history entry {index:04}: ");
                let mut value = String::with_capacity(HISTORY_ENTRY_BYTES);
                value.push_str(&prefix);
                value.extend(std::iter::repeat_n(
                    char::from(b'a' + (index % 26) as u8),
                    HISTORY_ENTRY_BYTES - prefix.len(),
                ));
                v_string(value)
            })
            .collect::<Vec<_>>();
        Self(v_list(&entries))
    }
}

fn encode_large_string_history(
    context: &mut LargeStringHistory,
    chunk_size: usize,
    _chunk_num: usize,
) {
    for _ in 0..chunk_size {
        let flatbuffer = var_to_db_flatbuffer(&context.0).unwrap();
        let mut builder = Builder::new();
        let encoded = builder.finish(flatbuffer, None);
        black_box(encoded);
    }
}

fn encode_large_string_history_direct(
    context: &mut LargeStringHistory,
    chunk_size: usize,
    _chunk_num: usize,
) {
    let mut builder = Builder::new();
    for _ in 0..chunk_size {
        let encoded = encode_db_var(&mut builder, &context.0).unwrap();
        black_box(encoded);
    }
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some("all or any benchmark name substring".to_string()),
        runtime: BenchmarkRuntimeOptions {
            warm_up_duration: Duration::from_millis(250),
            benchmark_duration: Duration::from_secs(1),
            min_samples: 8,
            max_samples: 24,
        },
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        runner.group::<LargeStringHistory>("Var FlatBuffer Encoding", |group| {
            let group = group.throughput(Throughput::bytes(
                (HISTORY_ENTRY_COUNT * HISTORY_ENTRY_BYTES) as u64,
            ));
            group.bench("large_string_history_owned", encode_large_string_history);
            group.bench(
                "large_string_history_direct",
                encode_large_string_history_direct,
            );
        });
    }
);
