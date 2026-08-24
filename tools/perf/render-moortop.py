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
import datetime
import json
import math
import os
import re
import sys
import uuid
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

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

OUTCOME_NAMES = {
    (0, 0): "success",
    (0, 1): "conflict",
    (0, 2): "error",
    (1, 0): "read_only_success",
    (1, 1): "write_success",
    (1, 2): "conflict",
    (1, 3): "rebase_exhausted",
    (2, 0): "success",
    (2, 1): "error",
    (3, 0): "completed",
    (4, 0): "success",
    (4, 1): "conflict",
    (5, 0): "completed",
    (6, 0): "cas_lost",
    (6, 1): "published",
    (7, 0): "cas_lost",
    (7, 1): "published",
    (7, 2): "overlap",
    (8, 0): "success",
    (8, 1): "encode_error",
    (8, 2): "enqueue_error",
}

BEGIN = re.compile(r"^MOORTOP_BEGIN ([0-9]+)")
END = re.compile(r"^MOORTOP_END ([0-9]+)")
U64_MASK = (1 << 64) - 1


@dataclass(frozen=True)
class IntervalStats:
    count: int
    total: int
    percentile95: int


@dataclass(frozen=True)
class VerbCallIntervalStats:
    started: int
    completed: int
    total: int
    percentile95: int


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


def verb_identity(key: tuple[int, ...], names: dict[str, str]) -> str:
    high, low, definer = key
    if high == 0 and low == 0:
        return "non-MOO"
    verb_uuid = uuid.UUID(int=((high & U64_MASK) << 64) | (low & U64_MASK))
    if str(verb_uuid) in names:
        return f"{object_name(definer)}:{names[str(verb_uuid)]}"
    return f"{object_name(definer)} {verb_uuid}"


def fitted_identity(identity: str, width: int = 45) -> str:
    if len(identity) <= width:
        return identity
    return f"{identity[: width - 1]}…"


def map_key(raw: str) -> tuple[int, ...]:
    raw = raw.strip().removeprefix("[").removesuffix("]")
    if not raw:
        return ()
    return tuple(int(part.strip()) for part in raw.split(","))


def keyed_map(frame: dict[str, object], name: str) -> dict[str, object]:
    value = frame.get(name)
    return value if isinstance(value, dict) else {}


def merge_frame_data(frame: dict[str, object], data: dict[str, object]) -> None:
    for name, value in data.items():
        previous = frame.get(name)
        if isinstance(previous, dict) and isinstance(value, dict):
            previous.update(value)
            continue
        frame[name] = value


def merged_numeric(
    frame: dict[str, object],
    name: str,
    identity_length: int,
) -> dict[tuple[int, ...], int]:
    merged: dict[tuple[int, ...], int] = defaultdict(int)
    for raw_key, raw_value in keyed_map(frame, name).items():
        try:
            key = map_key(raw_key)
            value = int(raw_value)
        except (AttributeError, TypeError, ValueError):
            continue
        if len(key) == identity_length + 1:
            key = key[1:]
        if len(key) != identity_length:
            continue
        merged[key] += value
    return dict(merged)


def merged_histograms(
    frame: dict[str, object],
    name: str,
    identity_length: int,
) -> dict[tuple[int, ...], dict[tuple[int, int], int]]:
    merged: dict[tuple[int, ...], dict[tuple[int, int], int]] = defaultdict(
        lambda: defaultdict(int)
    )
    for raw_key, raw_buckets in keyed_map(frame, name).items():
        try:
            key = map_key(raw_key)
        except (AttributeError, ValueError):
            continue
        if len(key) == identity_length + 1:
            key = key[1:]
        if len(key) != identity_length or not isinstance(raw_buckets, list):
            continue
        try:
            for bucket in raw_buckets:
                minimum = int(bucket["min"])
                maximum = int(bucket.get("max", minimum))
                count = int(bucket["count"])
                merged[key][(minimum, maximum)] += count
        except (KeyError, TypeError, ValueError):
            continue
    return {key: dict(buckets) for key, buckets in merged.items()}


def numeric_delta(
    current: dict[tuple[int, ...], int],
    previous: dict[tuple[int, ...], int],
) -> dict[tuple[int, ...], int]:
    return {
        key: value - previous.get(key, 0)
        for key, value in current.items()
        if value > previous.get(key, 0)
    }


def histogram_delta(
    current: dict[tuple[int, ...], dict[tuple[int, int], int]],
    previous: dict[tuple[int, ...], dict[tuple[int, int], int]],
) -> dict[tuple[int, ...], dict[tuple[int, int], int]]:
    result: dict[tuple[int, ...], dict[tuple[int, int], int]] = {}
    for key, buckets in current.items():
        old_buckets = previous.get(key, {})
        delta = {
            bucket: count - old_buckets.get(bucket, 0)
            for bucket, count in buckets.items()
            if count > old_buckets.get(bucket, 0)
        }
        if delta:
            result[key] = delta
    return result


def percentile95(buckets: dict[tuple[int, int], int]) -> int:
    count = sum(buckets.values())
    if count == 0:
        return 0
    target = max(1, math.ceil(count * 0.95))
    cumulative = 0
    for (_, maximum), bucket_count in sorted(buckets.items()):
        cumulative += bucket_count
        if cumulative >= target:
            return maximum
    return max(maximum for _, maximum in buckets)


def interval_stats(
    current: dict[str, object],
    previous: dict[str, object],
    prefix: str,
    identity_length: int,
) -> dict[tuple[int, ...], IntervalStats]:
    counts = numeric_delta(
        merged_numeric(current, f"@{prefix}_count", identity_length),
        merged_numeric(previous, f"@{prefix}_count", identity_length),
    )
    totals = numeric_delta(
        merged_numeric(current, f"@{prefix}_total", identity_length),
        merged_numeric(previous, f"@{prefix}_total", identity_length),
    )
    histograms = histogram_delta(
        merged_histograms(current, f"@{prefix}_hist", identity_length),
        merged_histograms(previous, f"@{prefix}_hist", identity_length),
    )

    stats: dict[tuple[int, ...], IntervalStats] = {}
    for key in set(counts) | set(totals) | set(histograms):
        count = counts.get(key, 0)
        total = totals.get(key, 0)
        if count <= 0 or total <= 0:
            continue
        stats[key] = IntervalStats(count, total, percentile95(histograms.get(key, {})))
    return stats


def verb_call_interval_stats(
    current: dict[str, object],
    previous: dict[str, object],
) -> dict[tuple[int, ...], VerbCallIntervalStats]:
    started = numeric_delta(
        merged_numeric(current, "@verb_call_started", 3),
        merged_numeric(previous, "@verb_call_started", 3),
    )
    completed = interval_stats(current, previous, "verb_call", 3)
    return {
        key: VerbCallIntervalStats(
            started=started.get(key, 0),
            completed=completed[key].count if key in completed else 0,
            total=completed[key].total if key in completed else 0,
            percentile95=completed[key].percentile95 if key in completed else 0,
        )
        for key in set(started) | set(completed)
    }


def print_section(
    title: str,
    rows: list[tuple[str, IntervalStats]],
    interval_seconds: float,
    limit: int,
    count_label: str = "count",
) -> None:
    print(f"\n{title}")
    if not rows:
        print("  no completed intervals")
        return

    denominator = sum(stats.total for _, stats in rows)
    interval_nanoseconds = interval_seconds * 1_000_000_000
    print(
        "% section  % core  identity                                       rate/s"
        f" {count_label:>7}       total        mean        p95~"
    )
    for identity, stats in sorted(rows, key=lambda row: row[1].total, reverse=True)[
        :limit
    ]:
        share = 100 * stats.total / denominator if denominator else 0.0
        core_share = (
            100 * stats.total / interval_nanoseconds if interval_nanoseconds else 0.0
        )
        mean = stats.total // stats.count
        print(
            f"    {share:>6.2f}  {core_share:>6.2f}  {fitted_identity(identity):<45}"
            f" {stats.count / interval_seconds:>7.1f}"
            f" {stats.count:>7} {duration(stats.total):>11}"
            f" {duration(mean):>11} {duration(stats.percentile95):>11}"
        )


def print_verb_call_section(
    rows: list[tuple[str, VerbCallIntervalStats]],
    interval_seconds: float,
    limit: int,
) -> None:
    print("\nMOO verb calls (sorted by completed-call elapsed total)")
    if not rows:
        print("  no verb calls started or completed in this interval")
        return

    denominator = sum(stats.total for _, stats in rows)
    print(
        "% elapsed  identity                                      start/s"
        "  started   done  elapsed total  elapsed mean  elapsed p95~"
    )
    for identity, stats in sorted(
        rows,
        key=lambda row: (row[1].total, row[1].started),
        reverse=True,
    )[:limit]:
        share = 100 * stats.total / denominator if denominator else 0.0
        mean = stats.total // stats.completed if stats.completed else 0
        print(
            f"    {share:>6.2f}  {fitted_identity(identity):<45}"
            f" {stats.started / interval_seconds:>7.1f}"
            f" {stats.started:>8} {stats.completed:>6}"
            f" {duration(stats.total):>14} {duration(mean):>13}"
            f" {duration(stats.percentile95):>13}"
        )


def load_builtin_names(path: Path | None) -> dict[int, str]:
    if path is None:
        return {}
    with path.open(encoding="utf-8") as source:
        raw_names = json.load(source)
    if not isinstance(raw_names, dict):
        raise ValueError("builtin map is not a JSON object")
    return {
        int(builtin_id): name
        for builtin_id, name in raw_names.items()
        if isinstance(name, str)
    }


def load_verb_names(path: Path | None) -> dict[str, str]:
    if path is None:
        return {}
    with path.open(encoding="utf-8") as source:
        raw_names = json.load(source)
    if not isinstance(raw_names, dict):
        raise ValueError("verb map is not a JSON object")

    names: dict[str, str] = {}
    for raw_uuid, name in raw_names.items():
        if not isinstance(raw_uuid, str) or not isinstance(name, str):
            raise ValueError("verb map entries must map UUID strings to names")
        names[str(uuid.UUID(raw_uuid))] = name
    return names


def live_verb_names(frame: dict[str, object]) -> dict[str, str]:
    names: dict[str, str] = {}
    for raw_key, name in keyed_map(frame, "@verb_names").items():
        if not isinstance(name, str):
            continue
        try:
            high, low, _ = map_key(raw_key)
        except (AttributeError, ValueError):
            continue
        verb_uuid = uuid.UUID(int=((high & U64_MASK) << 64) | (low & U64_MASK))
        names[str(verb_uuid)] = name
    return names


def live_verb_name_lengths(frame: dict[str, object]) -> dict[str, int]:
    lengths: dict[str, int] = {}
    for raw_key, raw_length in keyed_map(frame, "@verb_name_lengths").items():
        try:
            high, low, _ = map_key(raw_key)
            name_length = int(raw_length)
        except (AttributeError, TypeError, ValueError):
            continue
        verb_uuid = uuid.UUID(int=((high & U64_MASK) << 64) | (low & U64_MASK))
        lengths[str(verb_uuid)] = name_length
    return lengths


def scalar(frame: dict[str, object], name: str) -> int:
    try:
        return int(frame.get(name, 0))
    except (TypeError, ValueError):
        return 0


def write_verb_map(path: Path, names: dict[str, str]) -> None:
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    temporary.write_text(
        json.dumps(names, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def printf_text(data: object) -> str:
    if isinstance(data, str):
        return data
    if isinstance(data, dict):
        for key in ("formatted", "text", "message"):
            value = data.get(key)
            if isinstance(value, str):
                return value
        for value in data.values():
            if isinstance(value, str):
                return value
    return ""


def render(
    current: dict[str, object],
    previous: dict[str, object],
    interval_seconds: float,
    pid: int,
    limit: int,
    builtin_names: dict[int, str],
    verb_names: dict[str, str],
    clear_screen: bool,
    warnings: list[str],
    verb_map_output: Path | None,
) -> None:
    task_stats = interval_stats(current, previous, "task", 3)
    verb_call_stats = verb_call_interval_stats(current, previous)
    verb_stats = interval_stats(current, previous, "verb", 3)
    builtin_stats = interval_stats(current, previous, "builtin", 1)
    stage_stats = interval_stats(current, previous, "stage", 1)
    active = merged_numeric(current, "@active", 1)

    if clear_screen:
        print("\033[2J\033[H", end="")
    else:
        print("\n" + "=" * 123)

    now = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"mootop  PID {pid}  last {interval_seconds:.3f}s  {now}")
    print(
        "active: "
        f"tasks={max(0, active.get((0,), 0))}  "
        f"MOO calls={max(0, active.get((1,), 0))}  "
        f"MOO={max(0, active.get((2,), 0))}  "
        f"builtins={max(0, active.get((3,), 0))}  "
        f"commit stages={max(0, active.get((4,), 0))}"
    )
    if verb_map_output is not None:
        print(f"verb metadata: names={len(verb_names)} map={verb_map_output}")
    for warning in dict.fromkeys(warnings):
        print(f"WARNING: {warning}")

    print_section(
        "Task execution slices by root verb (sorted by interval total)",
        [(verb_identity(key, verb_names), stats) for key, stats in task_stats.items()],
        interval_seconds,
        limit,
        count_label="slices",
    )
    print_verb_call_section(
        [
            (verb_identity(key, verb_names), stats)
            for key, stats in verb_call_stats.items()
        ],
        interval_seconds,
        limit,
    )
    print_section(
        "MOO interpreter slices by verb (sorted by interval total)",
        [(verb_identity(key, verb_names), stats) for key, stats in verb_stats.items()],
        interval_seconds,
        limit,
        count_label="slices",
    )
    print_section(
        "Native builtin slices (sorted by interval total)",
        [
            (builtin_names.get(key[0], f"builtin_id={key[0]}"), stats)
            for key, stats in builtin_stats.items()
        ],
        interval_seconds,
        limit,
        count_label="slices",
    )
    print_section(
        "Database commit stages (sorted by interval total)",
        [
            (STAGE_NAMES.get(key[0], f"stage={key[0]}"), stats)
            for key, stats in stage_stats.items()
        ],
        interval_seconds,
        limit,
        count_label="done",
    )

    current_outcomes = merged_numeric(current, "@stage_outcome", 2)
    previous_outcomes = merged_numeric(previous, "@stage_outcome", 2)
    outcomes = numeric_delta(current_outcomes, previous_outcomes)
    if outcomes:
        print("\nCommit outcomes in this interval")
        totals: dict[int, int] = defaultdict(int)
        for (stage, _), count in outcomes.items():
            totals[stage] += count
        for (stage, outcome), count in sorted(outcomes.items()):
            stage_name = STAGE_NAMES.get(stage, f"stage={stage}")
            outcome_name = OUTCOME_NAMES.get((stage, outcome), str(outcome))
            share = 100 * count / totals[stage]
            print(
                f"  {share:>6.2f}%  {stage_name:<20}"
                f" outcome={outcome_name:<20} count={count}"
            )
    sys.stdout.flush()


def main() -> None:
    parser = argparse.ArgumentParser(description="Render live mooR BPF counters")
    parser.add_argument("--pid", type=int, required=True, help="target process ID")
    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
        help="expected first sampling interval in seconds",
    )
    parser.add_argument("--limit", type=int, default=10, help="rows per section")
    parser.add_argument("--builtin-map", type=Path, help="builtin ID map")
    parser.add_argument("--verb-map", type=Path, help="verb UUID map")
    parser.add_argument(
        "--verb-map-output",
        type=Path,
        help="write attached-process verb metadata to this JSON file",
    )
    parser.add_argument(
        "--no-clear",
        action="store_true",
        help="append each screen instead of clearing the terminal",
    )
    args = parser.parse_args()

    builtin_names = load_builtin_names(args.builtin_map)
    verb_names = load_verb_names(args.verb_map)
    previous: dict[str, object] = {}
    previous_timestamp = 0
    last_metadata_generation = 0
    attached_verb_names: dict[str, str] = {}
    metadata_warnings: list[str] = []
    frame: dict[str, object] | None = None
    warnings: list[str] = []
    pending_warnings: list[str] = []

    try:
        for line in sys.stdin:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            record_type = record.get("type")
            data = record.get("data")
            if record_type == "lost_events":
                pending_warnings.append("bpftrace lost output events")
                continue
            if record_type == "helper_error":
                helper = record.get("helper", "unknown helper")
                retcode = record.get("retcode")
                if (helper == "map_update_elem" and retcode == -17) or (
                    helper in {"map_delete_elem", "map_lookup_elem"} and retcode == -2
                ):
                    continue
                message = record.get("msg", "helper call failed")
                pending_warnings.append(f"{helper}: {message}")
                continue
            if record_type == "printf":
                message = printf_text(data)
                begin = BEGIN.match(message)
                if begin:
                    frame = {}
                    warnings = pending_warnings
                    pending_warnings = []
                    continue
                end = END.match(message)
                if end and frame is not None:
                    timestamp = int(end.group(1))
                    interval_seconds = args.interval
                    if previous_timestamp:
                        interval_seconds = (timestamp - previous_timestamp) / 1e9
                    interval_seconds = max(interval_seconds, 1e-9)
                    generation = scalar(frame, "@verb_metadata_generation")
                    if generation > last_metadata_generation:
                        metadata_warnings = []
                        live_names = live_verb_names(frame)
                        name_lengths = live_verb_name_lengths(frame)
                        attached_verb_names.update(live_names)
                        metadata_complete = True
                        status = frame.get("@verb_metadata_status")
                        if isinstance(status, list) and len(status) == 2:
                            try:
                                expected_names = int(status[0])
                                metadata_errors = int(status[1])
                            except (TypeError, ValueError):
                                expected_names = -1
                                metadata_errors = 1
                            if metadata_errors:
                                metadata_complete = False
                                metadata_warnings.append(
                                    f"verb metadata scan reported {metadata_errors} errors"
                                )
                            if expected_names != len(live_names):
                                metadata_complete = False
                                metadata_warnings.append(
                                    "verb metadata received "
                                    f"{len(live_names)} of {expected_names} names"
                                )
                        else:
                            metadata_complete = False
                            metadata_warnings.append(
                                "verb metadata status is unavailable"
                            )
                        truncated = sum(
                            len(name.encode("utf-8")) != name_lengths.get(verb_uuid)
                            for verb_uuid, name in live_names.items()
                        )
                        if truncated:
                            metadata_complete = False
                            metadata_warnings.append(
                                f"{truncated} verb names exceeded BPFTRACE_MAX_STRLEN"
                            )
                        if metadata_complete and args.verb_map_output is not None:
                            write_verb_map(
                                args.verb_map_output,
                                attached_verb_names,
                            )
                        last_metadata_generation = generation
                    resolved_verb_names = dict(verb_names)
                    resolved_verb_names.update(attached_verb_names)
                    render(
                        frame,
                        previous,
                        interval_seconds,
                        args.pid,
                        args.limit,
                        builtin_names,
                        resolved_verb_names,
                        sys.stdout.isatty() and not args.no_clear,
                        [*warnings, *metadata_warnings],
                        args.verb_map_output,
                    )
                    previous = frame
                    previous_timestamp = timestamp
                    frame = None
                    continue

            if frame is None:
                continue
            if record_type in {"map", "hist"} and isinstance(data, dict):
                merge_frame_data(frame, data)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
