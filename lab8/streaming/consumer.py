"""Share of failed payments per paymentMethod in one-minute event-time windows.

Share = failure / (success + failure), counted on the two final statuses only:
created and processing events say nothing about the outcome.

Each partition has its own largest modifiedDate; the watermark is the smallest of
them, so one partition read ahead of the others does not make their events look
late. A window closes when the watermark passes its end plus --lateness seconds.
An event for a window that has already closed is rejected as late and counted.

Offsets are committed after each batch, so a restart resumes where the consumer
stopped. The open windows and the set of seen events live in memory and do not
survive a restart.

    python consumer.py --group lab8 --lateness 120
"""

import argparse
import json
import signal
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from kafka import KafkaConsumer

WINDOW = timedelta(minutes=1)
ALERT_ABOVE = 0.10
FINAL = ("success", "failure")


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


class FailureWindows:
    def __init__(self, lateness: timedelta, min_final: int) -> None:
        self.lateness = lateness
        self.min_final = min_final
        self.seen: set[tuple[str, str]] = set()  # grows without limit; see the lab notes
        self.open: dict[datetime, dict[str, list[int]]] = {}
        self.partition_marks: dict[int, datetime] = {}
        self.assigned: set[int] = set()
        self.stats = defaultdict(int)

    def assign(self, partitions: set[int]) -> None:
        """Forget partitions taken away by a rebalance, or the watermark would stall on them."""
        self.assigned = partitions
        self.partition_marks = {p: t for p, t in self.partition_marks.items() if p in partitions}

    def watermark(self) -> datetime | None:
        if not self.assigned or set(self.partition_marks) != self.assigned:
            return None
        return min(self.partition_marks.values())

    def is_closed(self, start: datetime) -> bool:
        mark = self.watermark()
        return mark is not None and start + WINDOW + self.lateness <= mark

    def add(self, partition: int, event: dict) -> None:
        self.stats["received"] += 1
        key = (event["invoiceId"], event["status"])
        if key in self.seen:
            self.stats["duplicates"] += 1
            return
        self.seen.add(key)
        self.stats["unique"] += 1

        moment = parse_time(event["modifiedDate"])
        if partition not in self.partition_marks or moment > self.partition_marks[partition]:
            self.partition_marks[partition] = moment

        start = moment.replace(second=0)
        is_final = event["status"] in FINAL
        if self.is_closed(start):
            self.stats["rejected_late"] += 1
            self.stats["rejected_late_final"] += is_final
        elif is_final:
            counts = self.open.setdefault(start, defaultdict(lambda: [0, 0]))
            counts[event["paymentMethod"]][event["status"] == "failure"] += 1
            self.stats["counted_final"] += 1
        self.close_ready()

    def close_ready(self, everything: bool = False) -> None:
        for start in sorted(self.open):
            if not everything and not self.is_closed(start):
                break
            self.report(start, self.open.pop(start))

    def report(self, start: datetime, counts: dict[str, list[int]]) -> None:
        self.stats["windows"] += 1
        parts = []
        for method, (ok, failed) in sorted(counts.items()):
            total = ok + failed
            parts.append(f"{method}={failed}/{total}")
            if failed / total > ALERT_ABOVE and total >= self.min_final:
                self.stats["alerts"] += 1
                print(f"ALERT {start:%H:%M} {method}: {failed}/{total} = {failed / total:.0%} failed")
        print(f"window {start:%H:%M}  " + "  ".join(parts), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default="payments")
    parser.add_argument("--group", default="lab8")
    parser.add_argument("--lateness", type=int, default=120, help="seconds to wait for late events")
    parser.add_argument(
        "--min-final",
        type=int,
        default=1,
        help="alert only if the method has at least this many final events in the window",
    )
    parser.add_argument("--idle-exit", type=int, help="stop after this many idle seconds")
    parser.add_argument("--broker", default="localhost:19092")
    args = parser.parse_args()

    consumer = KafkaConsumer(
        args.topic,
        bootstrap_servers=args.broker,
        group_id=args.group,
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        value_deserializer=json.loads,
    )
    windows = FailureWindows(timedelta(seconds=args.lateness), args.min_final)

    stopping = []
    signal.signal(signal.SIGTERM, lambda *_: stopping.append(True))
    signal.signal(signal.SIGINT, lambda *_: stopping.append(True))

    idle_seconds = 0
    per_partition = defaultdict(int)
    print(f"group={args.group} topic={args.topic} lateness={args.lateness}s", flush=True)
    while not stopping:
        batches = consumer.poll(timeout_ms=1000)
        assigned = {tp.partition for tp in consumer.assignment()}
        if assigned != windows.assigned:
            print(f"partitions assigned: {sorted(assigned)}", flush=True)
            windows.assign(assigned)
        if not batches:
            idle_seconds += 1
            if args.idle_exit and idle_seconds >= args.idle_exit:
                break
            continue
        idle_seconds = 0
        for tp, records in batches.items():
            per_partition[tp.partition] += len(records)
            for record in records:
                windows.add(tp.partition, record.value)
        consumer.commit()

    if args.idle_exit:
        windows.close_ready(everything=True)
    consumer.close()
    print(f"partitions read: {dict(sorted(per_partition.items()))}", flush=True)
    print(f"totals: {dict(windows.stats)}", flush=True)


if __name__ == "__main__":
    main()
