#!/usr/bin/env bash
# Part 3 experiments. Usage: PY=python ./experiments.sh day.jsonl
# Replays the day once (about 28 minutes). Experiments 1 and 2 run on the live stream;
# the baseline and experiment 4 read the same log again under new consumer groups.
set -u
DAY="$1"
PY="${PY:-python3}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/results/part3"
mkdir -p "$OUT"
rpk() { docker compose exec -T redpanda rpk "$@"; }
consumer() { "$PY" -u consumer.py "$@"; }

"$PY" -u producer.py "$DAY" --rate 20 > "$OUT/producer.log" 2>&1 &
PRODUCER=$!

# Experiment 1: stop one consumer for a minute, then start it again.
(
  "$PY" -u consumer.py --group exp1 > "$OUT/exp1_before_stop.log" 2>&1 &
  C=$!
  sleep 60
  kill -TERM "$C"; wait "$C"
  rpk group describe exp1 > "$OUT/exp1_lag_while_stopped_0s.txt" 2>&1
  sleep 60
  rpk group describe exp1 > "$OUT/exp1_lag_while_stopped_60s.txt" 2>&1
  consumer --group exp1 --idle-exit 30 > "$OUT/exp1_after_restart.log" 2>&1
) &
EXP1=$!

# Experiment 2: two consumers in one group, then one of them leaves.
(
  "$PY" -u consumer.py --group exp2 --idle-exit 30 > "$OUT/exp2_consumer_a.log" 2>&1 &
  A=$!
  sleep 30
  rpk group describe exp2 > "$OUT/exp2_group_one_member.txt" 2>&1
  "$PY" -u consumer.py --group exp2 > "$OUT/exp2_consumer_b.log" 2>&1 &
  B=$!
  sleep 30
  rpk group describe exp2 > "$OUT/exp2_group_two_members.txt" 2>&1
  sleep 60
  kill -TERM "$B"; wait "$B"
  sleep 20
  rpk group describe exp2 > "$OUT/exp2_group_after_b_left.txt" 2>&1
  wait "$A"
) &
EXP2=$!

wait "$PRODUCER" "$EXP1" "$EXP2"

# Experiment 4: one more live replay, three consumers with different waits at once.
# Live, because a consumer catching up from the log reads in big per-partition batches,
# and the watermark then lags by more than the wait, which hides the rejections.
docker compose exec -T redpanda rpk topic create payments-live -p 3 > /dev/null 2>&1
"$PY" -u producer.py "$DAY" --rate 20 --topic payments-live > "$OUT/exp4_producer.log" 2>&1 &
PRODUCER=$!
"$PY" -u consumer.py --topic payments-live --group live-120 --lateness 120 --idle-exit 30 > "$OUT/baseline_lateness_120.log" 2>&1 &
C1=$!
"$PY" -u consumer.py --topic payments-live --group live-0 --lateness 0 --idle-exit 30 > "$OUT/exp4_lateness_0.log" 2>&1 &
C2=$!
# A wait longer than the largest lateness in the data rejects nothing: the reference.
"$PY" -u consumer.py --topic payments-live --group live-660 --lateness 660 --idle-exit 30 > "$OUT/reference_lateness_660.log" 2>&1 &
C3=$!
wait "$PRODUCER" "$C1" "$C2" "$C3"

# Experiment 3: 30% of the successful payments are forced to fail, on a separate topic.
rpk topic create payments-fail -p 3 > /dev/null 2>&1
"$PY" -u producer.py "$DAY" --rate 20 --topic payments-fail --fail-share 0.3 > "$OUT/exp3_producer.log" 2>&1 &
PRODUCER=$!
consumer --topic payments-fail --group exp3 --idle-exit 30 > "$OUT/exp3_failures_30pct.log" 2>&1 &
CONSUMER=$!
wait "$PRODUCER" "$CONSUMER"
echo finished
