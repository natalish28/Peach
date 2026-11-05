"""Replay one day of payment events into the `payments` topic, in receivedAt order.

The pace is in payments per second; one payment is about three events. Sending in
receivedAt order is what makes late events arrive late, as they would in production.
invoiceId is the key, so all events of one payment land in one partition.

    python producer.py day.jsonl --rate 20
    python producer.py day.jsonl --rate 20 --fail-share 0.3   # experiment 3
"""

import argparse
import json
import random
import time

from kafka import KafkaProducer

EVENTS_PER_PAYMENT = 3


def load_events(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        events = [json.loads(line) for line in f]
    events.sort(key=lambda e: e["receivedAt"])
    return events


def force_failures(events: list[dict], share: float, seed: int = 8) -> None:
    """Turn a share of the successful payments into failures, duplicates included."""
    rng = random.Random(seed)
    invoices = sorted({e["invoiceId"] for e in events if e["status"] == "success"})
    failing = set(rng.sample(invoices, int(len(invoices) * share)))
    for e in events:
        if e["status"] == "success" and e["invoiceId"] in failing:
            e["status"] = "failure"
            e["finalAmount"] = 0
            e["failureReason"] = "Forced by experiment"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--rate", type=float, default=20, help="payments per second")
    parser.add_argument("--topic", default="payments")
    parser.add_argument("--fail-share", type=float, default=0)
    parser.add_argument("--limit", type=int, help="send only the first N events")
    parser.add_argument("--broker", default="localhost:19092")
    args = parser.parse_args()

    events = load_events(args.file)
    if args.fail_share:
        force_failures(events, args.fail_share)
    if args.limit:
        events = events[: args.limit]

    producer = KafkaProducer(
        bootstrap_servers=args.broker,
        key_serializer=str.encode,
        value_serializer=lambda e: json.dumps(e, ensure_ascii=False).encode(),
        acks="all",
    )

    pause = 1 / (args.rate * EVENTS_PER_PAYMENT)
    started = time.monotonic()
    for sent, event in enumerate(events, start=1):
        producer.send(args.topic, key=event["invoiceId"], value=event)
        # Sleep up to the schedule, not by a fixed pause, so send() time does not slow the rate.
        delay = started + sent * pause - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        if sent % 5000 == 0:
            print(f"sent {sent}/{len(events)}  receivedAt={event['receivedAt']}", flush=True)
    producer.flush()
    print(f"done: {len(events)} events in {time.monotonic() - started:.0f}s", flush=True)


if __name__ == "__main__":
    main()
