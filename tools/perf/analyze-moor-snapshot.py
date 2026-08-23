#!/usr/bin/env python3
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

import argparse
import collections
import json
import math
import re
import statistics
import uuid
from dataclasses import dataclass
from pathlib import Path

OUTCOME_NAMES = {
    ("task_commit", 0): "completed",
    ("db_prepare", 0): "success",
    ("db_prepare", 1): "error",
    ("db_total", 0): "read_only_success",
    ("db_total", 1): "write_success",
    ("db_total", 2): "conflict",
    ("db_total", 3): "rebase_exhausted",
    ("db_total", 4): "admission_rejected",
    ("db_read_only", 0): "completed",
    ("db_check", 0): "success",
    ("db_check", 1): "conflict",
    ("db_apply", 0): "completed",
    ("db_publish", 0): "cas_lost",
    ("db_publish", 1): "published",
    ("db_rebase", 0): "cas_lost",
    ("db_rebase", 1): "published",
    ("db_rebase", 2): "overlap",
    ("db_persist", 0): "success",
    ("db_persist", 1): "encode_error",
    ("db_persist", 2): "enqueue_error",
}

STAGE_NAMES = {
    0: "task_commit",
    1: "db_total",
    2: "db_prepare",
    3: "db_read_only",
    4: "db_check",
    5: "db_apply",
    6: "db_publish",
    7: "db_rebase",
    8: "db_persist",
}

UNMATCHED_NAMES = {
    **STAGE_NAMES,
    100: "task_run",
    101: "verb_run",
    102: "builtin_run",
}

EVENT_FIELD_COUNTS = {
    "capture_start": 2,
    "capture_end": 2,
    "task_run_start": 4,
    "task_run_done": 4,
    "verb_name": 7,
    "verb_run_start": 8,
    "verb_run_done": 8,
    "verb_pc": 8,
    "stage_start": 7,
    "stage_done": 5,
}

LOST_EVENTS = re.compile(r"^Lost ([0-9]+) events$")
U64_MASK = (1 << 64) - 1
WATCHLIST_MIN_SLICES = 20
COMMIT_ENVELOPE_STAGES = {"task_commit", "db_total"}
COMMIT_ATTENTION_OUTCOMES = {
    ("db_prepare", 1),
    ("db_total", 2),
    ("db_total", 3),
    ("db_total", 4),
    ("db_check", 1),
    ("db_publish", 0),
    ("db_rebase", 0),
    ("db_rebase", 2),
    ("db_persist", 1),
    ("db_persist", 2),
}


@dataclass(frozen=True)
class Start:
    timestamp: int
    metadata: tuple[int, ...]


@dataclass(frozen=True)
class AggregateStats:
    count: int
    total: int
    maximum: int
    percentile95: int


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction))]


def duration(value: int) -> str:
    if value >= 1_000_000_000:
        return f"{value / 1_000_000_000:.3f}s"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.3f}ms"
    if value >= 1_000:
        return f"{value / 1_000:.3f}us"
    return f"{value}ns"


def object_name(raw: int) -> str:
    raw &= U64_MASK
    kind = raw >> 62
    if kind != 0:
        return f"0x{raw:016x}"
    value = raw & 0xFFFF_FFFF
    if value >= 0x8000_0000:
        value -= 0x1_0000_0000
    return f"#{value}"


def verb_name(
    high: int,
    low: int,
    definer: int,
    names: set[str] | None = None,
) -> str:
    verb_uuid = uuid.UUID(int=((high & U64_MASK) << 64) | (low & U64_MASK))
    if names:
        display_names = " | ".join(sorted(names))
        return f"{object_name(definer)}:{display_names}"
    return f"{object_name(definer)} {verb_uuid}"


def fitted_identity(identity: str, width: int = 45) -> str:
    if len(identity) <= width:
        return identity
    return f"{identity[: width - 1]}…"


def print_summary(
    title: str,
    rows: list[tuple[str, list[int]]],
    limit: int,
    percentage_label: str,
    percentage_denominator: int | None = None,
    percentages_valid: bool = True,
) -> None:
    print(f"\n{title}")
    if not rows:
        print("  no completed intervals")
        return

    if percentage_denominator is None:
        percentage_denominator = sum(sum(values) for _, values in rows)

    print(
        f"  {percentage_label:>10}  identity                                      count"
        "       total         mean          p95          max"
    )
    for identity, values in sorted(rows, key=lambda row: sum(row[1]), reverse=True)[
        :limit
    ]:
        total = sum(values)
        percentage = (
            f"{100 * total / percentage_denominator:>9.2f}%"
            if percentages_valid and percentage_denominator
            else f"{'--':>10}"
        )
        print(
            f"  {percentage}  {fitted_identity(identity):<45} {len(values):>6}"
            f" {duration(total):>11}"
            f" {duration(int(statistics.mean(values))):>12}"
            f" {duration(percentile(values, 0.95)):>12}"
            f" {duration(max(values)):>12}"
        )


def parse_legacy(path: Path, limit: int) -> None:
    starts: dict[tuple[str, int], Start] = {}
    task_durations: dict[int, list[int]] = collections.defaultdict(list)
    verb_durations: dict[tuple[int, int, int], list[int]] = collections.defaultdict(
        list
    )
    verb_names: dict[tuple[int, int, int], set[str]] = collections.defaultdict(set)
    stage_durations: dict[str, list[int]] = collections.defaultdict(list)
    stage_outcomes: collections.Counter[tuple[str, int]] = collections.Counter()
    pc_samples: collections.Counter[tuple[int, int, int, int]] = collections.Counter()
    unmatched_done: collections.Counter[str] = collections.Counter()
    capture_start = 0
    capture_end = 0
    events: list[tuple[int, int, list[str]]] = []
    ignored_lines = 0
    lost_events = 0
    loss_reports = 0

    with path.open(encoding="utf-8") as source:
        for sequence, line in enumerate(source):
            line = line.rstrip("\n")
            if not line:
                continue

            fields = line.split("\t")
            event = fields[0]
            expected_fields = EVENT_FIELD_COUNTS.get(event)
            if expected_fields is None:
                lost_match = LOST_EVENTS.fullmatch(line)
                if lost_match:
                    lost_events += int(lost_match.group(1))
                    loss_reports += 1
                else:
                    ignored_lines += 1
                continue
            if len(fields) != expected_fields:
                ignored_lines += 1
                continue
            if event == "capture_start":
                capture_start = int(fields[1])
                continue
            if event == "capture_end":
                capture_end = int(fields[1])
                continue
            if event == "verb_name":
                key = tuple(int(field) for field in fields[2:5])
                try:
                    original_length = int(fields[5])
                    name_bytes = bytes.fromhex(fields[6])
                except ValueError:
                    ignored_lines += 1
                    continue
                if len(name_bytes) < original_length:
                    name = f"{name_bytes.decode('utf-8', errors='replace')}…"
                else:
                    try:
                        name = name_bytes.decode("utf-8")
                    except UnicodeDecodeError:
                        ignored_lines += 1
                        continue
                verb_names[key].add(name)
                continue
            events.append((int(fields[1]), sequence, fields))

    for timestamp, _, fields in sorted(events):
        event = fields[0]
        tid = int(fields[2])
        if event == "task_run_start":
            starts[("task_run", tid)] = Start(timestamp, (int(fields[3]),))
            continue
        if event == "task_run_done":
            start = starts.pop(("task_run", tid), None)
            if start is None:
                unmatched_done["task_run"] += 1
                continue
            task_durations[start.metadata[0]].append(timestamp - start.timestamp)
            continue
        if event == "verb_run_start":
            starts[("verb_run", tid)] = Start(
                timestamp,
                tuple(int(field) for field in fields[3:8]),
            )
            continue
        if event == "verb_run_done":
            start = starts.pop(("verb_run", tid), None)
            if start is None:
                unmatched_done["verb_run"] += 1
                continue
            _, high, low, definer, _ = start.metadata
            verb_durations[(high, low, definer)].append(timestamp - start.timestamp)
            continue
        if event == "verb_pc":
            high, low, definer, pc = (int(field) for field in fields[4:8])
            pc_samples[(high, low, definer, pc)] += 1
            continue
        if event == "stage_start":
            stage = fields[3]
            starts[(stage, tid)] = Start(
                timestamp,
                tuple(int(field) for field in fields[4:7]),
            )
            continue
        if event == "stage_done":
            stage = fields[3]
            outcome = int(fields[4])
            start = starts.pop((stage, tid), None)
            if start is None:
                unmatched_done[stage] += 1
                continue
            stage_durations[stage].append(timestamp - start.timestamp)
            stage_outcomes[(stage, outcome)] += 1

    elapsed = max(0, capture_end - capture_start)
    print(f"mooR runtime snapshot: {duration(elapsed)} captured")
    if lost_events:
        print(
            f"WARNING: bpftrace dropped {lost_events:,} events in "
            f"{loss_reports} bursts. Percentages are unavailable."
        )
    percentages_valid = lost_events == 0
    task_rows = [(str(task_id), values) for task_id, values in task_durations.items()]
    verb_rows = [
        (verb_name(*key, verb_names.get(key)), values)
        for key, values in verb_durations.items()
    ]
    stage_rows = [(stage, values) for stage, values in stage_durations.items()]
    print_summary(
        "Task execution cost by task and root verb (sorted by total)",
        task_rows,
        limit,
        "% section",
        percentages_valid=percentages_valid,
    )
    print_summary(
        "MOO interpreter cost by verb (sorted by total)",
        verb_rows,
        limit,
        "% section",
        percentages_valid=percentages_valid,
    )
    task_commit_total = sum(stage_durations.get("task_commit", []))
    print_summary(
        "Database commit-stage cost (sorted by total)",
        stage_rows,
        limit,
        "% commit",
        task_commit_total,
        percentages_valid,
    )

    print("\nCommit outcomes")
    if not stage_outcomes:
        print("  no completed commit stages")
    outcome_totals = collections.Counter[str]()
    for (stage, _), count in stage_outcomes.items():
        outcome_totals[stage] += count
    for (stage, outcome), count in sorted(stage_outcomes.items()):
        outcome_name = OUTCOME_NAMES.get((stage, outcome), str(outcome))
        percentage = (
            f"{100 * count / outcome_totals[stage]:>6.2f}%"
            if percentages_valid
            else f"{'--':>7}"
        )
        print(f"  {percentage}  {stage:<20} outcome={outcome_name:<20} count={count}")

    print("\nSampled MOO program counters")
    if not pc_samples:
        print("  no program-counter samples")
    total_pc_samples = pc_samples.total()
    for (high, low, definer, pc), count in pc_samples.most_common(limit):
        percentage = (
            f"{100 * count / total_pc_samples:>6.2f}%"
            if percentages_valid
            else f"{'--':>7}"
        )
        print(
            f"  {percentage}  "
            f"{fitted_identity(verb_name(high, low, definer, verb_names.get((high, low, definer)))):<45}"
            f" pc={pc:<5}"
            f" samples={count}"
        )

    active = []
    for (kind, tid), start in starts.items():
        if kind == "verb_run":
            _, high, low, definer, pc = start.metadata
            identity = (
                f"{verb_name(high, low, definer, verb_names.get((high, low, definer)))}"
                f" pc_start={pc}"
            )
        else:
            identity = ",".join(str(value) for value in start.metadata)
        active.append((capture_end - start.timestamp, kind, tid, identity))

    print("\nIntervals active at capture end")
    if not active:
        print("  none observed")
    for elapsed_ns, kind, tid, identity in sorted(active, reverse=True)[:limit]:
        print(f"  {duration(elapsed_ns):>12}  {kind:<20} tid={tid:<8} {identity}")

    if unmatched_done:
        if lost_events:
            print("\nUnmatched interval completions")
            print(
                "  Starts can be absent because capture began mid-interval or events were dropped."
            )
        else:
            print("\nIntervals already active when capture started")
        for kind, count in sorted(unmatched_done.items()):
            print(f"  {kind:<20} completions_without_start={count}")

    if ignored_lines:
        print(f"\nIgnored non-event output lines: {ignored_lines}")

    aggregate_verb_rows = [
        (
            identity,
            AggregateStats(
                len(values),
                sum(values),
                max(values),
                percentile(values, 0.95),
            ),
        )
        for identity, values in verb_rows
    ]
    aggregate_stage_rows = [
        (
            identity,
            AggregateStats(
                len(values),
                sum(values),
                max(values),
                percentile(values, 0.95),
            ),
        )
        for identity, values in stage_rows
    ]
    print_performance_watchlist(
        aggregate_verb_rows,
        [],
        aggregate_stage_rows,
        [
            (stage, outcome, count)
            for (stage, outcome), count in stage_outcomes.items()
        ],
        percentages_valid,
    )


def map_key(raw: str) -> tuple[int, ...]:
    return tuple(int(part.strip()) for part in raw.split(","))


def merge_json_map(
    destination: dict[str, object],
    name: str,
    value: object,
) -> None:
    previous = destination.get(name)
    if isinstance(previous, dict) and isinstance(value, dict):
        previous.update(value)
        return
    destination[name] = value


def read_aggregate_data(
    path: Path,
) -> tuple[dict[str, object], dict[str, object], int, list[str], int]:
    maps: dict[str, object] = {}
    histograms: dict[str, object] = {}
    lost_events = 0
    helper_errors: list[str] = []
    ignored_lines = 0

    with path.open(encoding="utf-8") as source:
        for line in source:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                ignored_lines += 1
                continue

            record_type = record.get("type")
            data = record.get("data", {})
            if record_type in {"map", "hist"} and isinstance(data, dict):
                destination = maps if record_type == "map" else histograms
                for name, value in data.items():
                    merge_json_map(destination, name, value)
                continue
            if record_type == "lost_events" and isinstance(data, dict):
                lost_events += int(data.get("events", 0))
                continue
            if record_type == "helper_error":
                helper = record.get("helper", "unknown helper")
                retcode = record.get("retcode")
                if (helper == "map_update_elem" and retcode == -17) or (
                    helper == "map_delete_elem" and retcode == -2
                ):
                    continue
                message = record.get("msg", "helper call failed")
                line_number = record.get("line")
                location = f" at line {line_number}" if line_number is not None else ""
                helper_errors.append(f"{helper}{location}: {message}")
                continue
            if record_type not in {"attached_probes"}:
                ignored_lines += 1

    return maps, histograms, lost_events, helper_errors, ignored_lines


def keyed_map(
    maps: dict[str, object],
    name: str,
    protocol_errors: list[str],
) -> dict[tuple[int, ...], object]:
    raw = maps.get(name)
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        protocol_errors.append(f"{name} is not a keyed map")
        return {}

    parsed: dict[tuple[int, ...], object] = {}
    for raw_key, value in raw.items():
        try:
            parsed[map_key(raw_key)] = value
        except (AttributeError, ValueError):
            protocol_errors.append(f"{name} has an invalid key: {raw_key!r}")
    return parsed


def numeric_map(
    maps: dict[str, object],
    name: str,
    protocol_errors: list[str],
) -> dict[tuple[int, ...], int]:
    parsed = keyed_map(maps, name, protocol_errors)
    numeric: dict[tuple[int, ...], int] = {}
    for key, value in parsed.items():
        try:
            numeric[key] = int(value)
        except (TypeError, ValueError):
            protocol_errors.append(f"{name}[{key}] is not an integer")
    return numeric


def tuple_map(
    maps: dict[str, object],
    name: str,
    lengths: set[int],
    protocol_errors: list[str],
) -> dict[tuple[int, ...], tuple[int, ...]]:
    parsed = keyed_map(maps, name, protocol_errors)
    tuples: dict[tuple[int, ...], tuple[int, ...]] = {}
    for key, value in parsed.items():
        if not isinstance(value, list) or len(value) not in lengths:
            expected = " or ".join(str(length) for length in sorted(lengths))
            protocol_errors.append(f"{name}[{key}] is not a {expected}-element tuple")
            continue
        try:
            tuples[key] = tuple(int(element) for element in value)
        except (TypeError, ValueError):
            protocol_errors.append(f"{name}[{key}] contains a non-integer value")
    return tuples


def scalar_map(
    maps: dict[str, object],
    name: str,
    protocol_errors: list[str],
) -> int:
    raw = maps.get(name)
    if raw is None:
        protocol_errors.append(f"{name} is absent")
        return 0
    try:
        return int(raw)
    except (TypeError, ValueError):
        protocol_errors.append(f"{name} is not an integer")
        return 0


def histogram_percentile(
    buckets: object,
    count: int,
    map_name: str,
    key: tuple[int, ...],
    protocol_errors: list[str],
) -> int:
    if not isinstance(buckets, list):
        protocol_errors.append(f"{map_name}[{key}] is not a histogram")
        return 0

    parsed_buckets: list[tuple[int, int, int]] = []
    try:
        for bucket in buckets:
            minimum = int(bucket["min"])
            maximum = int(bucket.get("max", minimum))
            bucket_count = int(bucket["count"])
            parsed_buckets.append((minimum, maximum, bucket_count))
    except (KeyError, TypeError, ValueError):
        protocol_errors.append(f"{map_name}[{key}] has an invalid bucket")
        return 0

    observed = sum(bucket_count for _, _, bucket_count in parsed_buckets)
    if observed != count:
        protocol_errors.append(
            f"{map_name}[{key}] contains {observed} samples, expected {count}"
        )
    if not parsed_buckets:
        return 0

    target = max(1, math.ceil(count * 0.95))
    cumulative = 0
    ordered_buckets = sorted(parsed_buckets)
    for _, maximum, bucket_count in ordered_buckets:
        cumulative += bucket_count
        if cumulative >= target:
            return maximum
    return ordered_buckets[-1][1]


def logical_key(
    key: tuple[int, ...],
    identity_lengths: set[int],
    map_name: str,
    protocol_errors: list[str],
) -> tuple[int, ...] | None:
    if len(key) in identity_lengths:
        return key
    if len(key) - 1 in identity_lengths:
        return key[1:]
    protocol_errors.append(f"{map_name} has an invalid key: {key}")
    return None


def merge_numeric_shards(
    values: dict[tuple[int, ...], int],
    identity_lengths: set[int],
    map_name: str,
    protocol_errors: list[str],
    take_maximum: bool = False,
) -> dict[tuple[int, ...], int]:
    merged: dict[tuple[int, ...], int] = {}
    for key, value in values.items():
        identity = logical_key(key, identity_lengths, map_name, protocol_errors)
        if identity is None:
            continue
        if take_maximum:
            merged[identity] = max(merged.get(identity, 0), value)
        else:
            merged[identity] = merged.get(identity, 0) + value
    return merged


def merge_histogram_shards(
    values: dict[tuple[int, ...], object],
    identity_lengths: set[int],
    map_name: str,
    protocol_errors: list[str],
) -> dict[tuple[int, ...], list[dict[str, int]]]:
    merged: dict[tuple[int, ...], dict[tuple[int, int], int]] = collections.defaultdict(
        dict
    )
    for key, buckets in values.items():
        identity = logical_key(key, identity_lengths, map_name, protocol_errors)
        if identity is None:
            continue
        if not isinstance(buckets, list):
            protocol_errors.append(f"{map_name}[{key}] is not a histogram")
            continue
        try:
            for bucket in buckets:
                minimum = int(bucket["min"])
                maximum = int(bucket.get("max", minimum))
                bucket_count = int(bucket["count"])
                bucket_key = (minimum, maximum)
                merged[identity][bucket_key] = (
                    merged[identity].get(bucket_key, 0) + bucket_count
                )
        except (KeyError, TypeError, ValueError):
            protocol_errors.append(f"{map_name}[{key}] has an invalid bucket")

    return {
        identity: [
            {"min": minimum, "max": maximum, "count": count}
            for (minimum, maximum), count in sorted(buckets.items())
        ]
        for identity, buckets in merged.items()
    }


def aggregate_stats(
    maps: dict[str, object],
    histograms: dict[str, object],
    prefix: str,
    identity_lengths: set[int],
    protocol_errors: list[str],
) -> dict[tuple[int, ...], AggregateStats]:
    counts = merge_numeric_shards(
        numeric_map(maps, f"@{prefix}_count", protocol_errors),
        identity_lengths,
        f"@{prefix}_count",
        protocol_errors,
    )
    totals = merge_numeric_shards(
        numeric_map(maps, f"@{prefix}_total", protocol_errors),
        identity_lengths,
        f"@{prefix}_total",
        protocol_errors,
    )
    maxima = merge_numeric_shards(
        numeric_map(maps, f"@{prefix}_max", protocol_errors),
        identity_lengths,
        f"@{prefix}_max",
        protocol_errors,
        take_maximum=True,
    )
    raw_histograms = merge_histogram_shards(
        keyed_map(histograms, f"@{prefix}_hist", protocol_errors),
        identity_lengths,
        f"@{prefix}_hist",
        protocol_errors,
    )
    keys = set(counts) | set(totals) | set(maxima) | set(raw_histograms)
    stats: dict[tuple[int, ...], AggregateStats] = {}

    for key in keys:
        missing = [
            name
            for name, values in (
                ("count", counts),
                ("total", totals),
                ("max", maxima),
                ("hist", raw_histograms),
            )
            if key not in values
        ]
        if missing:
            protocol_errors.append(
                f"@{prefix} maps omit {', '.join(missing)} for key {key}"
            )
            continue

        count = counts[key]
        if count <= 0 or totals[key] < 0 or maxima[key] < 0:
            protocol_errors.append(f"@{prefix} maps have invalid values for key {key}")
            continue
        percentile95 = histogram_percentile(
            raw_histograms[key],
            count,
            f"@{prefix}_hist",
            key,
            protocol_errors,
        )
        stats[key] = AggregateStats(count, totals[key], maxima[key], percentile95)

    return stats


def percentage(value: int, denominator: int, valid: bool, width: int) -> str:
    if not valid:
        return f"{'--':>{width}}"
    result = 100 * value / denominator if denominator else 0.0
    return f"{result:>{width - 1}.2f}%"


def print_aggregate_summary(
    title: str,
    rows: list[tuple[str, AggregateStats]],
    limit: int,
    percentage_label: str,
    percentages_valid: bool,
    percentage_denominator: int | None = None,
) -> None:
    print(f"\n{title}")
    if not rows:
        print("  no completed intervals")
        return

    if percentage_denominator is None:
        percentage_denominator = sum(stats.total for _, stats in rows)

    print(
        f"  {percentage_label:>10}  identity                                      count"
        "       total         mean         p95~          max"
    )
    for identity, stats in sorted(rows, key=lambda row: row[1].total, reverse=True)[
        :limit
    ]:
        mean = stats.total // stats.count if stats.count else 0
        print(
            f"  {percentage(stats.total, percentage_denominator, percentages_valid, 10)}"
            f"  {fitted_identity(identity):<45} {stats.count:>6}"
            f" {duration(stats.total):>11}"
            f" {duration(mean):>12}"
            f" {duration(stats.percentile95):>12}"
            f" {duration(stats.maximum):>12}"
        )


def print_performance_watchlist(
    verb_rows: list[tuple[str, AggregateStats]],
    builtin_rows: list[tuple[str, AggregateStats]],
    stage_rows: list[tuple[str, AggregateStats]],
    outcome_rows: list[tuple[str, int, int]],
    percentages_valid: bool,
) -> None:
    print("\nTL;DR: performance places to watch")
    if not percentages_valid:
        print("  unavailable because the capture data is incomplete or inconsistent")
        return

    printed = False
    verb_total = sum(stats.total for _, stats in verb_rows)
    if verb_total:
        print("  Largest aggregate MOO costs:")
        for identity, stats in sorted(
            verb_rows, key=lambda row: row[1].total, reverse=True
        )[:3]:
            share = 100 * stats.total / verb_total
            print(
                f"    {share:>6.2f}%  {fitted_identity(identity):<45}"
                f" total={duration(stats.total)} slices={stats.count:,}"
            )
        printed = True

    tail_rows = [
        row for row in verb_rows if row[1].count >= WATCHLIST_MIN_SLICES
    ]
    if tail_rows:
        identity, stats = max(
            tail_rows,
            key=lambda row: (row[1].percentile95, row[1].total),
        )
        print(
            f"  Highest well-sampled MOO tail: {fitted_identity(identity)}"
            f" p95~={duration(stats.percentile95)} across {stats.count:,} slices"
        )
        printed = True

    builtin_total = sum(stats.total for _, stats in builtin_rows)
    if builtin_total:
        print("  Largest aggregate builtin costs:")
        for identity, stats in sorted(
            builtin_rows, key=lambda row: row[1].total, reverse=True
        )[:3]:
            share = 100 * stats.total / builtin_total
            print(
                f"    {share:>6.2f}%  {fitted_identity(identity):<45}"
                f" total={duration(stats.total)} slices={stats.count:,}"
            )
        printed = True

    builtin_tail_rows = [
        row for row in builtin_rows if row[1].count >= WATCHLIST_MIN_SLICES
    ]
    if builtin_tail_rows:
        identity, stats = max(
            builtin_tail_rows,
            key=lambda row: (row[1].percentile95, row[1].total),
        )
        print(
            f"  Highest well-sampled builtin tail: {fitted_identity(identity)}"
            f" p95~={duration(stats.percentile95)} across {stats.count:,} slices"
        )
        printed = True

    task_commit_total = next(
        (
            stats.total
            for identity, stats in stage_rows
            if identity == "task_commit"
        ),
        0,
    )
    commit_substages = [
        row for row in stage_rows if row[0] not in COMMIT_ENVELOPE_STAGES
    ]
    if task_commit_total and commit_substages:
        identity, stats = max(commit_substages, key=lambda row: row[1].total)
        share = 100 * stats.total / task_commit_total
        print(
            f"  Largest commit sub-stage: {identity}"
            f" {share:.2f}% of task_commit, p95~={duration(stats.percentile95)}"
        )
        printed = True

    outcome_totals = collections.Counter[str]()
    for stage, _, count in outcome_rows:
        outcome_totals[stage] += count
    attention_rows = [
        (stage, outcome, count)
        for stage, outcome, count in outcome_rows
        if count and (stage, outcome) in COMMIT_ATTENTION_OUTCOMES
    ]
    if attention_rows:
        print("  Commit contention or errors:")
        for stage, outcome, count in sorted(
            attention_rows,
            key=lambda row: row[2] / outcome_totals[row[0]],
            reverse=True,
        )[:3]:
            share = 100 * count / outcome_totals[stage]
            outcome_name = OUTCOME_NAMES[(stage, outcome)]
            print(f"    {stage} {outcome_name}: {share:.2f}% ({count:,})")
        printed = True

    if not printed:
        print("  no completed MOO, builtin, or commit intervals")


def parse_aggregate(
    path: Path,
    limit: int,
    builtin_names: dict[int, str],
) -> None:
    maps, histograms, lost_events, helper_errors, ignored_lines = read_aggregate_data(
        path
    )
    protocol_errors: list[str] = []
    capture_start = scalar_map(maps, "@capture_start", protocol_errors)
    capture_end = scalar_map(maps, "@capture_end", protocol_errors)
    task_stats = aggregate_stats(maps, histograms, "task", {1, 4}, protocol_errors)
    verb_stats = aggregate_stats(maps, histograms, "verb", {3}, protocol_errors)
    builtin_stats = aggregate_stats(
        maps, histograms, "builtin", {1}, protocol_errors
    )
    stage_stats = aggregate_stats(maps, histograms, "stage", {1}, protocol_errors)
    raw_names = keyed_map(maps, "@verb_names", protocol_errors)
    verb_names: dict[tuple[int, int, int], set[str]] = collections.defaultdict(set)
    for key, value in raw_names.items():
        if len(key) != 4 or not isinstance(value, str):
            protocol_errors.append(f"@verb_names has an invalid entry for key {key}")
            continue
        verb_names[(key[0], key[1], key[2])].add(value)

    task_rows: list[tuple[str, AggregateStats]] = []
    for key, stats in task_stats.items():
        if len(key) == 1:
            identity = str(key[0])
        elif len(key) == 4:
            task_id, high, low, definer = key
            verb_identity = (
                "non-MOO"
                if high == 0 and low == 0
                else verb_name(high, low, definer, verb_names.get((high, low, definer)))
            )
            identity = f"task={task_id} {verb_identity}"
        else:
            protocol_errors.append(f"@task maps have an invalid key: {key}")
            continue
        task_rows.append((identity, stats))

    verb_rows: list[tuple[str, AggregateStats]] = []
    for key, stats in verb_stats.items():
        if len(key) != 3:
            protocol_errors.append(f"@verb maps have an invalid key: {key}")
            continue
        verb_rows.append((verb_name(*key, verb_names.get(key)), stats))

    builtin_rows: list[tuple[str, AggregateStats]] = []
    for key, stats in builtin_stats.items():
        if len(key) != 1:
            protocol_errors.append(f"@builtin maps have an invalid key: {key}")
            continue
        builtin_id = key[0]
        identity = builtin_names.get(builtin_id, f"builtin_id={builtin_id}")
        builtin_rows.append((identity, stats))

    stage_rows: list[tuple[str, AggregateStats]] = []
    task_commit_total = 0
    for key, stats in stage_stats.items():
        if len(key) != 1 or key[0] not in STAGE_NAMES:
            protocol_errors.append(f"@stage maps have an invalid key: {key}")
            continue
        stage = STAGE_NAMES[key[0]]
        stage_rows.append((stage, stats))
        if stage == "task_commit":
            task_commit_total = stats.total

    stage_outcomes = merge_numeric_shards(
        numeric_map(maps, "@stage_outcome", protocol_errors),
        {2},
        "@stage_outcome",
        protocol_errors,
    )
    outcome_rows: list[tuple[str, int, int]] = []
    outcome_totals = collections.Counter[str]()
    for key, count in stage_outcomes.items():
        if len(key) != 2 or key[0] not in STAGE_NAMES:
            protocol_errors.append(f"@stage_outcome has an invalid key: {key}")
            continue
        stage = STAGE_NAMES[key[0]]
        outcome_rows.append((stage, key[1], count))
        outcome_totals[stage] += count

    pc_samples = merge_numeric_shards(
        numeric_map(maps, "@pc_samples", protocol_errors),
        {4},
        "@pc_samples",
        protocol_errors,
    )
    valid_pc_samples: list[tuple[tuple[int, int, int, int], int]] = []
    for key, count in pc_samples.items():
        if len(key) != 4:
            protocol_errors.append(f"@pc_samples has an invalid key: {key}")
            continue
        valid_pc_samples.append(((key[0], key[1], key[2], key[3]), count))

    task_states = tuple_map(maps, "@task_state", {2, 5}, protocol_errors)
    verb_states = tuple_map(maps, "@verb_state", {7}, protocol_errors)
    builtin_states = tuple_map(maps, "@builtin_state", {3}, protocol_errors)
    stage_starts = numeric_map(maps, "@stage_start", protocol_errors)
    active: list[tuple[int, str, int, str]] = []

    for key, state in task_states.items():
        if len(key) != 1:
            protocol_errors.append(f"@task_state has an invalid key: {key}")
            continue
        tid = key[0]
        if len(state) == 2:
            started, task_identity = state
            identity = str(task_identity)
        else:
            started, _, high, low, definer = state
            identity_key = (high, low, definer)
            identity = (
                "non-MOO task"
                if high == 0 and low == 0
                else verb_name(*identity_key, verb_names.get(identity_key))
            )
        active.append((max(0, capture_end - started), "task_run", tid, identity))

    for key, state in verb_states.items():
        if len(key) != 1:
            protocol_errors.append(f"@verb_state has an invalid key: {key}")
            continue
        tid = key[0]
        started, _, high, low, definer, pc_start, _ = state
        identity_key = (high, low, definer)
        identity = (
            f"{verb_name(*identity_key, verb_names.get(identity_key))}"
            f" pc_start={pc_start}"
        )
        active.append((max(0, capture_end - started), "verb_run", tid, identity))

    for key, state in builtin_states.items():
        if len(key) != 1:
            protocol_errors.append(f"@builtin_state has an invalid key: {key}")
            continue
        tid = key[0]
        started, task_id, builtin_id = state
        identity = builtin_names.get(builtin_id, f"builtin_id={builtin_id}")
        identity = f"task={task_id} {identity}"
        active.append((max(0, capture_end - started), "builtin_run", tid, identity))

    if not task_states and "@task_state" not in maps:
        task_starts = numeric_map(maps, "@task_start", protocol_errors)
        task_identities = numeric_map(maps, "@task_identity", protocol_errors)
        for key, started in task_starts.items():
            if len(key) != 1:
                protocol_errors.append(f"@task_start has an invalid key: {key}")
                continue
            if key not in task_identities:
                protocol_errors.append(f"@task_identity omits active key {key}")
            tid = key[0]
            identity = str(task_identities.get(key, 0))
            active.append((max(0, capture_end - started), "task_run", tid, identity))

    if not verb_states and "@verb_state" not in maps:
        verb_starts = numeric_map(maps, "@verb_start", protocol_errors)
        verb_high = numeric_map(maps, "@verb_uuid_high", protocol_errors)
        verb_low = numeric_map(maps, "@verb_uuid_low", protocol_errors)
        verb_definer = numeric_map(maps, "@verb_definer", protocol_errors)
        verb_pc = numeric_map(maps, "@verb_pc_start", protocol_errors)
        for key, started in verb_starts.items():
            if len(key) != 1:
                protocol_errors.append(f"@verb_start has an invalid key: {key}")
                continue
            metadata_maps = (verb_high, verb_low, verb_definer, verb_pc)
            if any(key not in metadata for metadata in metadata_maps):
                protocol_errors.append(f"active verb metadata omits key {key}")
            tid = key[0]
            identity_key = (
                verb_high.get(key, 0),
                verb_low.get(key, 0),
                verb_definer.get(key, 0),
            )
            identity = (
                f"{verb_name(*identity_key, verb_names.get(identity_key))}"
                f" pc_start={verb_pc.get(key, 0)}"
            )
            active.append((max(0, capture_end - started), "verb_run", tid, identity))

    for key, started in stage_starts.items():
        if len(key) != 2 or key[1] not in STAGE_NAMES:
            protocol_errors.append(f"@stage_start has an invalid key: {key}")
            continue
        tid, stage_id = key
        stage = STAGE_NAMES[stage_id]
        active.append((max(0, capture_end - started), stage, tid, ""))

    unmatched = merge_numeric_shards(
        numeric_map(maps, "@unmatched", protocol_errors),
        {1},
        "@unmatched",
        protocol_errors,
    )
    unmatched_rows: list[tuple[str, int]] = []
    for key, count in unmatched.items():
        if len(key) != 1 or key[0] not in UNMATCHED_NAMES:
            protocol_errors.append(f"@unmatched has an invalid key: {key}")
            continue
        unmatched_rows.append((UNMATCHED_NAMES[key[0]], count))

    if capture_end < capture_start:
        protocol_errors.append("@capture_end precedes @capture_start")
    for stage_id, stage in STAGE_NAMES.items():
        key = (stage_id,)
        completed = stage_stats[key].count if key in stage_stats else 0
        expected_outcomes = completed + unmatched.get(key, 0)
        if outcome_totals[stage] != expected_outcomes:
            protocol_errors.append(
                f"{stage} has {outcome_totals[stage]} outcomes, "
                f"expected {expected_outcomes}"
            )

    elapsed = max(0, capture_end - capture_start)
    percentages_valid = not lost_events and not helper_errors and not protocol_errors
    print(f"mooR runtime snapshot: {duration(elapsed)} captured")
    if lost_events:
        print(
            f"WARNING: bpftrace dropped {lost_events:,} output events. "
            "Percentages are unavailable."
        )
    if helper_errors:
        print("WARNING: bpftrace reported helper errors. Percentages are unavailable.")
        for message in dict.fromkeys(helper_errors):
            print(f"  {message}")
    if protocol_errors:
        print("WARNING: aggregate data is inconsistent. Percentages are unavailable.")
        for message in protocol_errors[:10]:
            print(f"  {message}")
        if len(protocol_errors) > 10:
            print(f"  {len(protocol_errors) - 10} more errors")

    print_aggregate_summary(
        "Task execution cost by task and root verb (sorted by total)",
        task_rows,
        limit,
        "% section",
        percentages_valid,
    )
    print_aggregate_summary(
        "MOO interpreter cost by verb (sorted by total)",
        verb_rows,
        limit,
        "% section",
        percentages_valid,
    )
    print_aggregate_summary(
        "Native builtin cost by builtin (sorted by total)",
        builtin_rows,
        limit,
        "% section",
        percentages_valid,
    )
    print_aggregate_summary(
        "Database commit-stage cost (sorted by total)",
        stage_rows,
        limit,
        "% commit",
        percentages_valid,
        task_commit_total,
    )

    print("\nCommit outcomes")
    if not outcome_rows:
        print("  no completed commit stages")
    for stage, outcome, count in sorted(outcome_rows):
        outcome_name = OUTCOME_NAMES.get((stage, outcome), str(outcome))
        print(
            f"  {percentage(count, outcome_totals[stage], percentages_valid, 7)}"
            f"  {stage:<20} outcome={outcome_name:<20} count={count}"
        )

    print("\nSampled MOO program counters")
    if not valid_pc_samples:
        print("  no program-counter samples")
    total_pc_samples = sum(count for _, count in valid_pc_samples)
    for (high, low, definer, pc), count in sorted(
        valid_pc_samples, key=lambda row: row[1], reverse=True
    )[:limit]:
        identity = fitted_identity(
            verb_name(high, low, definer, verb_names.get((high, low, definer)))
        )
        print(
            f"  {percentage(count, total_pc_samples, percentages_valid, 7)}"
            f"  {identity:<45} pc={pc:<5} samples={count}"
        )

    print("\nIntervals active at capture end")
    if not active:
        print("  none observed")
    for elapsed_ns, kind, tid, identity in sorted(active, reverse=True)[:limit]:
        print(f"  {duration(elapsed_ns):>12}  {kind:<20} tid={tid:<8} {identity}")

    if unmatched_rows:
        print("\nIntervals already active when capture started")
        for kind, count in sorted(unmatched_rows):
            print(f"  {kind:<20} completions_without_start={count}")

    if ignored_lines:
        print(f"\nIgnored bpftrace output lines: {ignored_lines}")

    print_performance_watchlist(
        verb_rows,
        builtin_rows,
        stage_rows,
        outcome_rows,
        percentages_valid,
    )


def load_builtin_names(path: Path | None) -> dict[int, str]:
    if path is None:
        return {}

    with path.open(encoding="utf-8") as source:
        raw_names = json.load(source)
    if not isinstance(raw_names, dict):
        raise ValueError(f"builtin map is not a JSON object: {path}")

    names: dict[int, str] = {}
    for raw_id, name in raw_names.items():
        try:
            builtin_id = int(raw_id)
        except (TypeError, ValueError) as error:
            raise ValueError(f"builtin map has an invalid ID: {raw_id!r}") from error
        if not isinstance(name, str):
            raise ValueError(f"builtin map name for ID {builtin_id} is not a string")
        names[builtin_id] = name
    return names


def parse(path: Path, limit: int, builtin_names: dict[int, str]) -> None:
    with path.open(encoding="utf-8") as source:
        first_line = next((line for line in source if line.strip()), "")
    if first_line.lstrip().startswith("{"):
        parse_aggregate(path, limit, builtin_names)
        return
    parse_legacy(path, limit)


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize a mooR USDT snapshot")
    parser.add_argument(
        "events",
        type=Path,
        help="aggregate JSON or legacy event file from moor-snapshot.bt",
    )
    parser.add_argument(
        "--limit", type=int, default=20, help="maximum rows per section"
    )
    parser.add_argument(
        "--builtin-map",
        type=Path,
        help="JSON map from builtin IDs to names",
    )
    args = parser.parse_args()
    parse(args.events, args.limit, load_builtin_names(args.builtin_map))


if __name__ == "__main__":
    main()
