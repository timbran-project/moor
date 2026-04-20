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
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, ConcurrentBenchContext,
    ConcurrentBenchControl, ConcurrentWorker, ConcurrentWorkerResult, Throughput, benchmark_main,
    black_box,
};
use moor_var::Symbol;
use std::{collections::HashMap, time::Duration};

// ============================================================================
// SYMBOL CREATION BENCHMARKS
// ============================================================================

// Pre-generate unique strings to avoid measuring string formatting overhead
struct UniqueStringsContext {
    strings: Vec<String>,
    index: usize,
}

impl BenchContext for UniqueStringsContext {
    fn prepare(num_chunks: usize) -> Self {
        let total = num_chunks.max(1) * Self::chunk_size().unwrap_or(1);
        let strings: Vec<String> = (0..total).map(|i| format!("unique_symbol_{i}")).collect();
        UniqueStringsContext { strings, index: 0 }
    }

    fn chunk_size() -> Option<usize> {
        Some(10_000) // Smaller chunk for creation since it's slower
    }
}

fn symbol_create_unique(ctx: &mut UniqueStringsContext, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        let s = &ctx.strings[ctx.index];
        ctx.index += 1;
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

// Context for repeated symbol lookups (cache hit path)
struct RepeatedSymbolContext {
    test_string: String,
}

impl BenchContext for RepeatedSymbolContext {
    fn prepare(_num_chunks: usize) -> Self {
        // Create the symbol once so it's in the interner AND in thread-local cache
        let test_string = "repeated_lookup_test".to_string();
        let _ = Symbol::mk(&test_string);
        RepeatedSymbolContext { test_string }
    }
}

fn symbol_lookup_cached(ctx: &mut RepeatedSymbolContext, chunk_size: usize, _chunk_num: usize) {
    let s = &ctx.test_string;
    for _ in 0..chunk_size {
        // This will hit the thread-local cache
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

// Context for case variant lookups
struct CaseVariantContext {
    variants: Vec<String>,
}

impl BenchContext for CaseVariantContext {
    fn prepare(_num_chunks: usize) -> Self {
        // Create initial symbol
        let _ = Symbol::mk("CaseVariantTest");
        CaseVariantContext {
            variants: vec![
                "CaseVariantTest".to_string(),
                "casevarianttest".to_string(),
                "CASEVARIANTTEST".to_string(),
                "caseVariantTest".to_string(),
            ],
        }
    }
}

fn symbol_lookup_case_variants(ctx: &mut CaseVariantContext, chunk_size: usize, _chunk_num: usize) {
    let variants = &ctx.variants;
    for i in 0..chunk_size {
        let s = &variants[i % variants.len()];
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

// ============================================================================
// SYMBOL STRING RETRIEVAL BENCHMARKS
// ============================================================================

struct SymbolRetrievalContext {
    symbols: Vec<Symbol>,
}

impl BenchContext for SymbolRetrievalContext {
    fn prepare(_num_chunks: usize) -> Self {
        // Create a variety of symbols
        let symbols: Vec<Symbol> = (0..100)
            .map(|i| Symbol::mk(&format!("retrieval_test_{i}")))
            .collect();
        SymbolRetrievalContext { symbols }
    }
}

fn symbol_as_string(ctx: &mut SymbolRetrievalContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let s = sym.as_string();
        black_box(s);
    }
}

fn symbol_as_arc_str(ctx: &mut SymbolRetrievalContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let s = sym.as_arc_str();
        black_box(s);
    }
}

// ============================================================================
// SYMBOL COMPARISON BENCHMARKS
// ============================================================================

struct SymbolCompareContext {
    sym1: Symbol,
    sym2_same: Symbol,
    sym2_case_variant: Symbol,
    sym3_different: Symbol,
}

impl BenchContext for SymbolCompareContext {
    fn prepare(_num_chunks: usize) -> Self {
        let sym1 = Symbol::mk("compare_test");
        let sym2_same = Symbol::mk("compare_test");
        let sym2_case_variant = Symbol::mk("COMPARE_TEST");
        let sym3_different = Symbol::mk("different_symbol");
        SymbolCompareContext {
            sym1,
            sym2_same,
            sym2_case_variant,
            sym3_different,
        }
    }
}

fn symbol_eq_same(ctx: &mut SymbolCompareContext, chunk_size: usize, _chunk_num: usize) {
    let sym1 = &ctx.sym1;
    let sym2 = &ctx.sym2_same;
    for _ in 0..chunk_size {
        let eq = sym1 == sym2;
        black_box(eq);
    }
}

fn symbol_eq_case_variant(ctx: &mut SymbolCompareContext, chunk_size: usize, _chunk_num: usize) {
    let sym1 = &ctx.sym1;
    let sym2 = &ctx.sym2_case_variant;
    for _ in 0..chunk_size {
        let eq = sym1 == sym2;
        black_box(eq);
    }
}

fn symbol_eq_different(ctx: &mut SymbolCompareContext, chunk_size: usize, _chunk_num: usize) {
    let sym1 = &ctx.sym1;
    let sym3 = &ctx.sym3_different;
    for _ in 0..chunk_size {
        let eq = sym1 == sym3;
        black_box(eq);
    }
}

// ============================================================================
// SYMBOL HASHING BENCHMARKS
// ============================================================================

struct SymbolHashContext {
    symbols: Vec<Symbol>,
    map: HashMap<Symbol, i32>,
}

impl BenchContext for SymbolHashContext {
    fn prepare(_num_chunks: usize) -> Self {
        let symbols: Vec<Symbol> = (0..1000)
            .map(|i| Symbol::mk(&format!("hash_test_{i}")))
            .collect();
        let mut map = HashMap::new();
        for (i, sym) in symbols.iter().enumerate() {
            map.insert(*sym, i as i32);
        }
        SymbolHashContext { symbols, map }
    }
}

fn symbol_hash_lookup(ctx: &mut SymbolHashContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    let map = &ctx.map;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let val = map.get(sym);
        black_box(val);
    }
}

fn symbol_hash_insert(ctx: &mut SymbolHashContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    let mut map = HashMap::new();
    for i in 0..chunk_size {
        let sym = symbols[i % symbols.len()];
        map.insert(sym, i as i32);
    }
    black_box(map);
}

// ============================================================================
// SYMBOL CLONE BENCHMARKS
// ============================================================================

struct SymbolCloneContext {
    sym: Symbol,
}

impl BenchContext for SymbolCloneContext {
    fn prepare(_num_chunks: usize) -> Self {
        SymbolCloneContext {
            sym: Symbol::mk("clone_test_symbol"),
        }
    }
}

fn symbol_clone(ctx: &mut SymbolCloneContext, chunk_size: usize, _chunk_num: usize) {
    let sym = ctx.sym;
    for _ in 0..chunk_size {
        let cloned = sym;
        black_box(cloned);
    }
}

// ============================================================================
// SYMBOL DISPLAY/DEBUG BENCHMARKS
// ============================================================================

fn symbol_display(ctx: &mut SymbolRetrievalContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let s = format!("{sym}");
        black_box(s);
    }
}

fn symbol_debug(ctx: &mut SymbolRetrievalContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let s = format!("{sym:?}");
        black_box(s);
    }
}

// ============================================================================
// SYMBOL SERIALIZATION BENCHMARKS
// ============================================================================

struct SymbolSerializeContext {
    symbols: Vec<Symbol>,
    serialized: Vec<String>,
}

impl BenchContext for SymbolSerializeContext {
    fn prepare(_num_chunks: usize) -> Self {
        let symbols: Vec<Symbol> = (0..100)
            .map(|i| Symbol::mk(&format!("serialize_test_{i}")))
            .collect();
        let serialized: Vec<String> = symbols
            .iter()
            .map(|s| serde_json::to_string(s).unwrap())
            .collect();
        SymbolSerializeContext {
            symbols,
            serialized,
        }
    }
}

fn symbol_serialize(ctx: &mut SymbolSerializeContext, chunk_size: usize, _chunk_num: usize) {
    let symbols = &ctx.symbols;
    for i in 0..chunk_size {
        let sym = &symbols[i % symbols.len()];
        let s = serde_json::to_string(sym).unwrap();
        black_box(s);
    }
}

fn symbol_deserialize(ctx: &mut SymbolSerializeContext, chunk_size: usize, _chunk_num: usize) {
    let serialized = &ctx.serialized;
    for i in 0..chunk_size {
        let s = &serialized[i % serialized.len()];
        let sym: Symbol = serde_json::from_str(s).unwrap();
        black_box(sym);
    }
}

// ============================================================================
// STRING LENGTH VARIATION BENCHMARKS
// ============================================================================

struct ShortStringContext {
    strings: Vec<String>,
}

impl BenchContext for ShortStringContext {
    fn prepare(_num_chunks: usize) -> Self {
        // 4-char strings
        let strings: Vec<String> = (0..1000).map(|i| format!("s{i:03}")).collect();
        // Intern them first
        for s in &strings {
            let _ = Symbol::mk(s);
        }
        ShortStringContext { strings }
    }
}

struct MediumStringContext {
    strings: Vec<String>,
}

impl BenchContext for MediumStringContext {
    fn prepare(_num_chunks: usize) -> Self {
        // ~20 char strings
        let strings: Vec<String> = (0..1000)
            .map(|i| format!("medium_length_str_{i:04}"))
            .collect();
        for s in &strings {
            let _ = Symbol::mk(s);
        }
        MediumStringContext { strings }
    }
}

struct LongStringContext {
    strings: Vec<String>,
}

impl BenchContext for LongStringContext {
    fn prepare(_num_chunks: usize) -> Self {
        // ~100 char strings
        let strings: Vec<String> = (0..1000)
            .map(|i| format!("this_is_a_very_long_symbol_name_that_might_be_used_for_method_names_or_properties_{i:04}"))
            .collect();
        for s in &strings {
            let _ = Symbol::mk(s);
        }
        LongStringContext { strings }
    }
}

fn symbol_lookup_short(ctx: &mut ShortStringContext, chunk_size: usize, _chunk_num: usize) {
    let strings = &ctx.strings;
    for i in 0..chunk_size {
        let s = &strings[i % strings.len()];
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

fn symbol_lookup_medium(ctx: &mut MediumStringContext, chunk_size: usize, _chunk_num: usize) {
    let strings = &ctx.strings;
    for i in 0..chunk_size {
        let s = &strings[i % strings.len()];
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

fn symbol_lookup_long(ctx: &mut LongStringContext, chunk_size: usize, _chunk_num: usize) {
    let strings = &ctx.strings;
    for i in 0..chunk_size {
        let s = &strings[i % strings.len()];
        let sym = Symbol::mk(s);
        black_box(sym);
    }
}

// ============================================================================
// CONCURRENT ACCESS BENCHMARKS
// ============================================================================

struct SharedSymbolContext {
    hot_symbol_str: String,
    hot_symbol: Symbol,
    case_variants: Vec<String>,
    short_strings: Vec<String>,
    long_strings: Vec<String>,
    unique_strings_per_thread: Vec<Vec<String>>,
}

impl ConcurrentBenchContext for SharedSymbolContext {
    fn prepare(num_threads: usize) -> Self {
        let hot_symbol_str = "tell".to_string();
        let hot_symbol = Symbol::mk(&hot_symbol_str);

        let case_variants = vec![
            "CaseVariantTest".to_string(),
            "casevarianttest".to_string(),
            "CASEVARIANTTEST".to_string(),
            "caseVariantTest".to_string(),
        ];
        for variant in &case_variants {
            let _ = Symbol::mk(variant);
        }

        let pool_size = (num_threads.max(1) * 128).max(256);
        let short_strings: Vec<String> = (0..pool_size).map(|i| format!("s{i:03}")).collect();
        let long_strings: Vec<String> = (0..pool_size)
            .map(|i| {
                format!(
                    "this_is_a_very_long_symbol_name_that_might_be_used_for_method_names_or_properties_{i:04}"
                )
            })
            .collect();
        for s in short_strings.iter().chain(long_strings.iter()) {
            let _ = Symbol::mk(s);
        }

        let unique_pool_size = 50_000;
        let unique_strings_per_thread: Vec<Vec<String>> = (0..num_threads.max(1))
            .map(|thread_idx| {
                (0..unique_pool_size)
                    .map(|i| format!("concurrent_unique_symbol_{thread_idx}_{i}"))
                    .collect()
            })
            .collect();

        SharedSymbolContext {
            hot_symbol_str,
            hot_symbol,
            case_variants,
            short_strings,
            long_strings,
            unique_strings_per_thread,
        }
    }
}

fn symbol_hot_path_lookup_concurrent(
    ctx: &SharedSymbolContext,
    control: &ConcurrentBenchControl,
) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        let sym = Symbol::mk(&ctx.hot_symbol_str);
        black_box(sym);
        operations = operations.wrapping_add(1);
    }
    ConcurrentWorkerResult::operations(operations)
}

fn symbol_case_variant_lookup_concurrent(
    ctx: &SharedSymbolContext,
    control: &ConcurrentBenchControl,
) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        let idx = (operations as usize + control.thread_index()) % ctx.case_variants.len();
        let sym = Symbol::mk(&ctx.case_variants[idx]);
        black_box(sym);
        operations = operations.wrapping_add(1);
    }
    ConcurrentWorkerResult::operations(operations)
}

fn symbol_mixed_lookup_concurrent(
    ctx: &SharedSymbolContext,
    control: &ConcurrentBenchControl,
) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        let idx = (operations as usize + control.thread_index()) % ctx.short_strings.len();
        let sym = match operations % 4 {
            0 => Symbol::mk(&ctx.hot_symbol_str),
            1 => Symbol::mk(&ctx.case_variants[idx % ctx.case_variants.len()]),
            2 => Symbol::mk(&ctx.short_strings[idx]),
            _ => Symbol::mk(&ctx.long_strings[idx % ctx.long_strings.len()]),
        };
        black_box(sym);
        operations = operations.wrapping_add(1);
    }
    ConcurrentWorkerResult::operations(operations)
}

fn symbol_create_unique_concurrent(
    ctx: &SharedSymbolContext,
    control: &ConcurrentBenchControl,
) -> ConcurrentWorkerResult {
    let thread_idx = control.thread_index() % ctx.unique_strings_per_thread.len();
    let strings = &ctx.unique_strings_per_thread[thread_idx];
    let mut operations = 0_u64;
    while !control.should_stop() {
        if operations as usize >= strings.len() {
            break;
        }
        let sym = Symbol::mk(&strings[operations as usize]);
        black_box(sym);
        operations = operations.wrapping_add(1);
    }
    ConcurrentWorkerResult::operations(operations)
}

fn symbol_hot_path_compare_id_concurrent(
    ctx: &SharedSymbolContext,
    control: &ConcurrentBenchControl,
) -> ConcurrentWorkerResult {
    let sym = ctx.hot_symbol;
    let mut operations = 0_u64;
    while !control.should_stop() {
        let id = sym.compare_id();
        black_box(id);
        operations = operations.wrapping_add(1);
    }
    ConcurrentWorkerResult::operations(operations)
}

// ============================================================================
// MAIN
// ============================================================================

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
        runner.group::<UniqueStringsContext>("Symbol Creation (Unique)", |g| {
            g.throughput(Throughput::per_operation(1, "symbols"))
                .bench("symbol_create_unique", symbol_create_unique);
        });

        runner.group::<RepeatedSymbolContext>("Symbol Creation (Cached)", |g| {
            g.throughput(Throughput::per_operation(1, "lookups"))
                .bench("symbol_lookup_cached", symbol_lookup_cached);
        });

        runner.group::<CaseVariantContext>("Symbol Creation (Case Variants)", |g| {
            g.throughput(Throughput::per_operation(1, "lookups"))
                .bench("symbol_lookup_case_variants", symbol_lookup_case_variants);
        });

        runner.group::<SymbolRetrievalContext>("Symbol Retrieval", |g| {
            let g = g.throughput(Throughput::per_operation(1, "retrievals"));
            g.bench("symbol_as_string", symbol_as_string);
            g.bench("symbol_as_arc_str", symbol_as_arc_str);
            g.bench("symbol_display", symbol_display);
            g.bench("symbol_debug", symbol_debug);
        });

        runner.group::<SymbolCompareContext>("Symbol Comparison", |g| {
            let g = g.throughput(Throughput::per_operation(1, "comparisons"));
            g.bench("symbol_eq_same", symbol_eq_same);
            g.bench("symbol_eq_case_variant", symbol_eq_case_variant);
            g.bench("symbol_eq_different", symbol_eq_different);
        });

        runner.group::<SymbolHashContext>("Symbol Hashing", |g| {
            let g = g.throughput(Throughput::per_operation(1, "hash_ops"));
            g.bench("symbol_hash_lookup", symbol_hash_lookup);
            g.bench("symbol_hash_insert", symbol_hash_insert);
        });

        runner.group::<SymbolCloneContext>("Symbol Clone", |g| {
            g.throughput(Throughput::per_operation(1, "symbols"))
                .bench("symbol_clone", symbol_clone);
        });

        runner.group::<SymbolSerializeContext>("Symbol Serialization", |g| {
            let g = g.throughput(Throughput::per_operation(1, "symbols"));
            g.bench("symbol_serialize", symbol_serialize);
            g.bench("symbol_deserialize", symbol_deserialize);
        });

        runner.group::<ShortStringContext>("Symbol Lookup (Short Strings)", |g| {
            g.throughput(Throughput::per_operation(1, "lookups"))
                .bench("symbol_lookup_short", symbol_lookup_short);
        });

        runner.group::<MediumStringContext>("Symbol Lookup (Medium Strings)", |g| {
            g.throughput(Throughput::per_operation(1, "lookups"))
                .bench("symbol_lookup_medium", symbol_lookup_medium);
        });

        runner.group::<LongStringContext>("Symbol Lookup (Long Strings)", |g| {
            g.throughput(Throughput::per_operation(1, "lookups"))
                .bench("symbol_lookup_long", symbol_lookup_long);
        });

        let max_threads = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1)
            .min(8);
        for &threads in &[1usize, 2, 4, 8] {
            if threads > max_threads {
                continue;
            }

            let readers = [ConcurrentWorker {
                name: "lookup_reader",
                threads,
                run: symbol_hot_path_lookup_concurrent,
            }];
            let case_variants = [ConcurrentWorker {
                name: "case_variant_reader",
                threads,
                run: symbol_case_variant_lookup_concurrent,
            }];
            let mixed = [ConcurrentWorker {
                name: "mixed_reader",
                threads,
                run: symbol_mixed_lookup_concurrent,
            }];
            let unique_creation = [ConcurrentWorker {
                name: "unique_creator",
                threads,
                run: symbol_create_unique_concurrent,
            }];
            let compare_id = [ConcurrentWorker {
                name: "compare_id_reader",
                threads,
                run: symbol_hot_path_compare_id_concurrent,
            }];

            runner.concurrent_group::<SharedSymbolContext>("Symbol Concurrent Access", |g| {
                g.sample_duration(Duration::from_millis(100))
                    .throughput(Throughput::per_operation(1, "lookups"))
                    .bench(&format!("symbol_hot_path_lookup_{threads}t"), &readers);
                g.sample_duration(Duration::from_millis(100))
                    .throughput(Throughput::per_operation(1, "lookups"))
                    .bench(
                        &format!("symbol_case_variant_lookup_{threads}t"),
                        &case_variants,
                    );
                g.sample_duration(Duration::from_millis(100))
                    .throughput(Throughput::per_operation(1, "lookups"))
                    .bench(&format!("symbol_mixed_lookup_{threads}t"), &mixed);
                g.sample_duration(Duration::from_millis(100))
                    .throughput(Throughput::per_operation(1, "symbols"))
                    .bench(
                        &format!("symbol_create_unique_{threads}t"),
                        &unique_creation,
                    );
                g.sample_duration(Duration::from_millis(100))
                    .throughput(Throughput::per_operation(1, "lookups"))
                    .bench(
                        &format!("symbol_hot_path_compare_id_{threads}t"),
                        &compare_id,
                    );
            });
        }
    }
);
