# Lab 8 — Two roads for the same data: batch and streaming

Everything is in [`lab8/`](lab8/): `athena/` (SQL and runner), `streaming/` (Redpanda, producer,
consumer), `cloud/` (cloud pipeline), `results/` (query results, consumer output).

**One deviation to flag:** this AWS account is on the Free plan, where Kinesis and Firehose answer
`SubscriptionRequiredException`. The Part 4 pipeline that actually ran therefore uses SQS and Lambda
in their place (details in Part 4). `cloud/kinesis-pipeline.yaml` describes the original services,
but it has only passed template validation and has never been deployed.

## Part 1 — Uklon's architecture

**What if the real-time road falls behind by 10 minutes? And batch by a day?**
Ten minutes on the real-time road hurts immediately: matching reads old driver positions, surge is
priced on demand that has already changed, alerts come too late to act on. Kinesis keeps the events,
so nothing is lost, but for matching the old pings are worthless, so the service should skip to the
latest position rather than work through the backlog. A day of delay on the batch road is
inconvenient and invisible to riders: dashboards are a day old and models train later. Raw data is
safe in S3 and the job can simply run again. Rides keep working.

**Why does GPS not go through Lambda?**
580 million pings a day is about 6,700 a second, around the clock. At the list prices (about $1 per
million API Gateway requests, $0.20 per million Lambda requests, before duration) the API Gateway
alone comes to roughly $17,000 a month. Every ping would also be a new HTTP request from the phone,
which costs battery and mobile data, and Lambda would need thousands of concurrent instances. A
persistent MQTT connection to IoT Core, feeding Kinesis in batches, fits a constant high-volume flow.

**What would a small startup drop first, and what would it lose?**

| Drop | Replace with | What it loses |
| --- | --- | --- |
| SageMaker | Simple ETA and demand rules | Accuracy of ETA and demand forecasts |
| Flink | A periodic query per district | Surge reacts in minutes, not seconds |
| DMS change data capture | Read replica or nightly export | Fresh database changes in the lake |
| Glue job, Quick | Athena over raw files, a free BI tool | Cheap scans; polished dashboards |
| IoT Core | HTTP pings, while volume is small | Battery life; breaks down as volume grows |

It would keep the core: one service, one database, raw events in S3.

## Part 2 — Batch on AWS

Bucket `peach-lab8-757159686525`. SQL is in `lab8/athena/sql/`, full results in
`lab8/results/part2/`. Copying needed `--copy-props none`, because the source bucket denies
`GetObjectTagging`. `dt=2026-10-31` holds only 2 KB: late events spilling past midnight of the 30th,
so the data is really 30 full days.

### Scale

| Question | Answer |
| --- | --- |
| Raw events | 3,030,197 |
| Unique `invoiceId` | 1,000,000 |
| Duplicate rows | 30,197 (3,000,000 distinct events) |
| Events more than 1 hour late | **0 of 3,000,000**; the largest lateness is exactly 600 s |

### Query results

**2. Deduplication.** The `payments` view returns 1,000,000 rows, one per invoice: 939,820 `success`
and 60,180 `failure`, with none left in `processing`.

**3. Turnover** (30 merchant and currency rows in `03_turnover_json.csv`). Total in UAH: 726,040,513.31.
Largest and smallest merchants in UAH:

| Merchant | Payments | Turnover, UAH |
| --- | --- | --- |
| m-009 Інтернет-магазин | 87,115 | 310,259,259.21 |
| m-008 АЗС | 87,560 | 144,641,341.06 |
| m-006 Музичний сервіс | 87,517 | 8,664,183.00 |

**4. Failure rate.** Among finished payments, from `qr/android` 6.71% down to `qr/ios` 5.92%. The top
of the list is `qr/android` 6.71, `apple_pay/android` 6.13, `google_pay/web` 6.08. Every combination
is close to 6%, and `qr` has the smallest sample (about 6,700 per device), so the ranking mostly
reflects noise: no method or device stands out.

**5. Peak hours (UTC).** The peak is 18:00 with 80,338 payments, with smaller peaks at 12:00 (66,304)
and 08:00 (59,947). The quietest hours are 00:00–04:00, about 6,600 each.

**6. Late events.** 60,231 of 3,000,000 distinct events (2.008%) arrived more than 60 s after they
happened, matching the 2% in the dataset's description.

**7. Parquet.** `curated/payments/`, 82.5 MB in 212 files, against 1.26 GB of JSON. Results of
queries 3–5 are identical on both.

### JSON against Parquet

Median engine time over 3–4 runs. Scan figures were the same on every run.

| Query | JSON scanned | JSON time | Parquet scanned | Parquet time | Less data scanned |
| --- | --- | --- | --- | --- | --- |
| 3 Turnover | 1,202.29 MB | 3.31 s | 6.11 MB | 0.88 s | 197× |
| 4 Failure rate | 1,202.29 MB | 3.00 s | 0.64 MB | 1.09 s | 1,879× |
| 5 Peak hours | 1,202.29 MB | 3.38 s | 6.25 MB | 1.32 s | 192× |

**How many times cheaper:** about **120×** per query in real money, not 197–1,879×. Athena charges
$5 per TB with a 10 MB minimum per query, so each Parquet query is billed as 10 MB ($0.00005) against
about $0.0057 for JSON. The saving comes from reading only the needed columns, and from compression.
Part of the time gain comes from the Parquet table being already deduplicated, so these queries skip
that step.

### Why `DISTINCT` comes before `row_number()`, and what breaks without deduplication

SQL computes window functions before `DISTINCT`. Once `row_number()` has given each row its own number,
no two rows are identical, so a `DISTINCT` applied afterwards removes nothing. It has to run in an
inner query, first. For this data, `rn = 1` alone would also leave one row per invoice, since exact
duplicates tie and only one gets number 1. The inner `DISTINCT` states the intent and sorts fewer
rows, and it matters as soon as the outer query uses `rank()` or needs event counts.

Without deduplication, on this data (`08_no_dedup_turnover.csv`):

| | Raw events | `payments` view |
| --- | --- | --- |
| Rows | 3,030,197 | 1,000,000 |
| Successes | 949,199 | 939,820 |
| Turnover, UAH | 733,128,678.76 | 726,040,513.31 |

Turnover is overstated by 7,088,165.45 UAH (0.98%), which is money reported that never arrived. And
counting raw rows as payments gives three times the real number.

### Way B — Glue Crawler

The crawler ran for 75 s and created `crawled_payments` (schema in `glue_crawler_schema.json`).

- **Types:** `amount` and `finalamount` are `int` (mine are `bigint`), `ccy` and `mcc` are `int`,
  all three dates are `string`, same as mine.
- **Partition:** yes, `dt` was recognised as a `string` partition, with all 31 loaded.
- **`failureReason`:** it became a normal `string` column, placed last. It is NULL where absent:
  60,779 values, equal to the number of `failure` events.
- **Other differences:** all names are lowercased, and its `recordCount` of 1,202,922 is an estimate
  (the real count is 3,030,197).
- **Which is more convenient:** the crawler for getting started, because it finds the schema and
  new partitions by itself. Queries are the same on both.
- **Why hand-written schemas are still common:** the types are a decision and not a guess from a
  sample (`int` is enough now, the largest `amount` is 8,004,389, but `bigint` is safe for money); the
  DDL lives in git and gets reviewed; and a new or odd field in the data cannot silently change the
  table under running queries.

## Part 3 — Streaming locally

`lab8/streaming/`: Redpanda and Console in Docker Compose, topic with 3 partitions, one day
(2026-10-15, 101,788 events) replayed in `receivedAt` order at 20 payments a second, taking 1,696 s,
with `invoiceId` as the key. Output is in `lab8/results/part3/`.

The consumer counts failure / (success + failure) in one-minute windows of `modifiedDate`. The
watermark is the smallest of the per-partition maximum event times; a window closes 2 minutes after
its end by that watermark.

Baseline, 2-minute wait: 101,788 received, 1,085 duplicates dropped, 100,703 unique, 33,003 final
events counted, 1,966 of them failures (5.96%), 1,431 windows.

**Reference:** with a wait longer than the largest lateness (660 s) nothing is rejected: 33,568 final
events and 2,022 failures. That equals the day's numbers computed directly from the file.

### Experiment 1 — stop for a minute, then restart

| Moment | Members | Total lag |
| --- | --- | --- |
| Just stopped | 0 | 15 |
| 60 s later | 0 | 3,629 |

The group's committed offset at the stop was 60,335; the restarted consumer read 41,453 events.
60,335 + 41,453 = 101,788, every event. **The log loses nothing.**

But the consumer's own state did not survive. Compared with the baseline:

| Windows | Final events, baseline | Final events, with restart |
| --- | --- | --- |
| 15:46–16:15, before the stop | 984 | 984 (identical) |
| 16:16–16:30, around the stop | 488 | 396 (**92 missing**) |
| 16:31–23:59, after it | 13,184 | 13,195 (+11) |

The missing events are those already read and committed, but held in windows that were still open,
in memory (16:21–16:23). Committing offsets before a window closes makes this possible. A real fix
keeps window state in a checkpoint committed together with the offsets, as Flink does. Also, window
16:20 was printed a second time after the restart, because the new process no longer knew it had
closed. The +11 most likely comes from the emptied `seen` set and a more forgiving watermark while
catching up; I did not trace it event by event.

*Note:* my first attempt at experiments 1 and 2 was invalid because a script bug left the consumer
running. These runs use the same group names, so `exp1` began at about offset 56,549, left committed
by that attempt, rather than 0. This is why the comparison above starts at 15:46.

### Experiment 2 — two consumers in one group

| Moment | Members | Partitions |
| --- | --- | --- |
| Consumer A alone | 1 | A: 0, 1, 2 |
| B joins | 2 | B: 0, 1; A: 2 |
| B leaves | 1 | A: 0, 1, 2 |

Lag stayed near 0 throughout, and A took over from B's committed offsets. The group, not the consumer,
owns the offsets. There are only 3 partitions, so a fourth consumer would sit idle. Each consumer now
sees only part of the payments, so per-window numbers need a shared state to be correct overall.

### Experiment 3 — producer fails 30% of payments

| | Baseline | 30% forced |
| --- | --- | --- |
| Failures among final events | 1,966 (5.96%) | 11,273 (34.16%) |
| Window and method cells above 10% | 882 of 4,421 | 3,390 of 4,421 |

Example: `ALERT 15:33 google_pay: 3/6 = 50% failed`.

The alert fired, but it also fires **882 times on normal data**, in 20% of cells, because windows are
small: 1 failure in 3 payments is 33%. Requiring a minimum sample separates the two far better:

| Minimum final events in the cell | Alerts, baseline | Alerts, 30% forced |
| --- | --- | --- |
| 1 (as specified) | 882 of 4,421 | 3,390 of 4,421 |
| 10 | 236 of 1,268 | 1,227 of 1,268 |
| 20 | 47 of 313 | 311 of 313 |

### Experiment 4 — no waiting for late events

| Wait | Events rejected as late | Final events rejected | Final counted | Failures counted | Share |
| --- | --- | --- | --- | --- | --- |
| 660 s | 0 | 0 | 33,568 | 2,022 | 6.02% |
| 120 s | 1,588 | 565 | 33,003 | 1,966 | 5.96% |
| **0 s** | **1,970** | **692** | 32,876 | 1,959 | 5.96% |

What changed in the windows:

- Between 120 s and 0 s, 125 of 4,421 cells differ, usually by one payment (`05:31 card: 1/10` becomes `1/9`).
- Going from 660 s to 0 s, 608 of 4,437 cells differ, and 16 disappear entirely.
- The overall share barely moves, and cells above 10% go from 891 to 882.

Lateness in this data is spread over 1–10 minutes, so a 2-minute wait saves only about a fifth of
the rejections (1,970 down to 1,588). Rejecting none takes a 10-minute wait, and each alert then comes
10 minutes later: the trade between complete and fast, in one number.

This experiment ran on a live replay. Replaying from a finished log gave far fewer rejections (840 at
0 s), because catching up in large per-partition batches holds the watermark back, so the wait is
effectively longer. Those runs are kept in `results/part3/log_replay_not_comparable/`.

### The `seen` set

It grew to 100,703 entries for one day and grows without limit, and it is lost on restart. In
production it goes in Redis or Flink state, with a TTL a little longer than the largest lateness: here
a duplicate can arrive up to about 10 minutes later, so a TTL of about 1 hour would be safe. Since all
events of a payment share a partition, this state can be split per partition too.

## Part 4 — Streaming in the cloud

**Pipeline** (`pipeline_diagram.png`), same payments dataset:

`producer.py` → SQS `lab8-payments` → Lambda `lab8-stream-writer` (batches up to 30 s) →
S3 `stream/dt=.../` → Athena `lab8.stream_events`; and Lambda → SNS `lab8-alerts` → SQS check queue.

- **Stand-ins:** SQS replaces Kinesis, and the Lambda batching window replaces the Firehose buffer.
- **Producer:** `lab8/cloud/producer.py`, which supports both `--sink sqs` and `--sink kinesis`; only
  `sqs` has been run.
- **Run:** 6,000 events in 147 s. From event 4,000 on, every successful payment was forced to fail.

**Athena over the stream** (screenshot attached; query `11_stream_query.sql`, results in
`results/part4/`): 6,000 events in 10 files, 1,981 invoices, 71 duplicate rows. The failure share per
batch file goes from 4.0–9.4% to 90–100% once the forced failures begin.

**Alert:** 13 SNS messages were delivered to the check queue, for example `card: 103/103 = 100% failed`.
Delivery went to a queue rather than e-mail, so no subscription had to be confirmed. The alert needs
at least 20 final events per method in a batch, a lesson from experiment 3.

### How it differs from local Redpanda

| | Redpanda (Part 3) | Cloud pipeline as run (SQS, Lambda) | Kinesis, Firehose (not run) |
| --- | --- | --- | --- |
| Reading again | Yes, from the log | **No**, a message is deleted once processed | Yes, within retention |
| Independent consumers | Consumer groups | One queue, one reader | Several |
| Order | Per partition, by key | Not guaranteed | Per shard, by key |
| Alert based on | Event-time windows, watermark | Each batch; arrival order, no event time | Same with Lambda; windows would need Flink |
| Deduplication | In the consumer | None (71 duplicates reach S3; dedupe in the view) | None at Firehose |
| Output | Console only | Durable files, queryable in SQL | Durable files, queryable in SQL |
| Operations | I run the broker | Nothing to run; scales by itself | Shards to size; billed by the hour |

The main lesson: SQS is a queue, not a log. It moves the data through, but the replay that saved
experiment 1 does not exist here.

### Cost

These are estimates from list prices; the bill itself was not checked, because it lags by a day.

- **Pipeline as run:** under $0.01. SQS requests (about 600 sends) and Lambda (10 invocations, about
  7 s) fall within the free allowances, and S3 is 2.5 MB.
- **All of Lab 8's Athena queries:** 25.88 GiB scanned, about $0.13.
- **Glue crawler:** one 75 s run, a few cents.
- **Kinesis and Firehose for comparison:** $0.015 per shard-hour and $0.029 per GB, so about $0.02 for
  one hour with this data. The real cost is forgetting to delete them: about $11 a month per shard.

**Cleanup:** stack `lab8-stream` is deleted (queues, Lambda, SNS), and no Kinesis or Firehose streams
were created. The S3 data and Athena tables remain for review.

## For the class discussion

- **Event time or processing time:** windows use `modifiedDate`, event time, so a replay at any speed
  gives the same windows. A late event within the wait is added; after it, it is rejected and counted.
- **JSON and Parquet both:** JSON is the untouched source, which can always be reprocessed if the
  logic has a bug. Parquet is the derived, deduplicated form that is about 120× cheaper to query.
- **Nightly or seconds:** decide by the cost of acting late. Turnover reports can wait for the night;
  a payment provider going down cannot.
- **Managed or self-run:** managed services remove brokers, upgrades and scaling, and they cost per
  hour or per GB, with limits like the Free plan restriction met here. Self-run is free per hour here,
  but all of the operations are yours.
