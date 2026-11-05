"""Replay payment events into the cloud pipeline, in receivedAt order.

    python producer.py day.jsonl --sink sqs --limit 6000 --fail-after 4000
    python producer.py day.jsonl --sink kinesis --limit 6000 --fail-after 4000

From event number --fail-after on, every successful payment becomes a failure,
so the second half of the run fires the alert.
"""

import argparse
import json
import time

import boto3

BATCH = {"kinesis": 500, "sqs": 10}  # the most one API call accepts


def load_events(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        events = [json.loads(line) for line in f]
    events.sort(key=lambda e: e["receivedAt"])
    return events


def send_kinesis(client, batch: list[dict]) -> None:
    records = [
        {"Data": json.dumps(e, ensure_ascii=False).encode() + b"\n", "PartitionKey": e["invoiceId"]}
        for e in batch
    ]
    while records:
        response = client.put_records(StreamName="lab8-payments", Records=records)
        # PutRecords can fail for single records (throttling) while the call succeeds.
        records = [
            record
            for record, result in zip(records, response["Records"])
            if "ErrorCode" in result
        ]
        if records:
            time.sleep(1)


def send_sqs(client, queue_url: str, batch: list[dict]) -> None:
    entries = [
        {"Id": str(i), "MessageBody": json.dumps(e, ensure_ascii=False)}
        for i, e in enumerate(batch)
    ]
    while entries:
        response = client.send_message_batch(QueueUrl=queue_url, Entries=entries)
        failed = {f["Id"] for f in response.get("Failed", [])}
        entries = [entry for entry in entries if entry["Id"] in failed]
        if entries:
            time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--sink", choices=BATCH, required=True)
    parser.add_argument("--rate", type=float, default=60, help="events per second")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--fail-after", type=int, help="fail every payment from this event on")
    args = parser.parse_args()

    events = load_events(args.file)[: args.limit]
    if args.fail_after is not None:
        for e in events[args.fail_after :]:
            if e["status"] == "success":
                e.update(status="failure", finalAmount=0, failureReason="Forced by experiment")

    if args.sink == "kinesis":
        client = boto3.client("kinesis")
        send = lambda batch: send_kinesis(client, batch)
    else:
        client = boto3.client("sqs")
        queue_url = client.get_queue_url(QueueName="lab8-payments")["QueueUrl"]
        send = lambda batch: send_sqs(client, queue_url, batch)

    size = BATCH[args.sink]
    started = time.monotonic()
    for sent in range(0, len(events), size):
        send(events[sent : sent + size])
        delay = started + (sent + size) / args.rate - time.monotonic()
        if delay > 0:
            time.sleep(delay)
    print(f"sent {len(events)} events in {time.monotonic() - started:.0f}s", flush=True)


if __name__ == "__main__":
    main()
