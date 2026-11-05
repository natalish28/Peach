"""Run the Lab 8 Athena queries in order; save each result as CSV plus a stats table.

    python run.py                 # everything, in order
    python run.py 03 04           # only the files whose names start with these prefixes

Queries with {table} run twice: on the JSON view and on the Parquet table.
"""

import csv
import sys
import time
from pathlib import Path

import boto3

BUCKET = "peach-lab8-757159686525"
HERE = Path(__file__).parent
OUT = HERE.parent / "results" / "part2"
TABLES = {"json": "lab8.payments", "parquet": "lab8.payments_parquet"}

athena = boto3.client("athena", region_name="us-east-1")
s3 = boto3.client("s3", region_name="us-east-1")


def run(sql: str, name: str) -> dict:
    qid = athena.start_query_execution(
        QueryString=sql,
        WorkGroup="primary",
        ResultConfiguration={"OutputLocation": f"s3://{BUCKET}/athena-results/"},
    )["QueryExecutionId"]
    while True:
        q = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = q["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if state != "SUCCEEDED":
        raise SystemExit(f"{name}: {state}: {q['Status'].get('StateChangeReason')}")

    stats = q["Statistics"]
    row = {
        "query": name,
        "execution_id": qid,
        "data_scanned_mb": round(stats.get("DataScannedInBytes", 0) / 1024**2, 2),
        "engine_time_s": round(stats.get("EngineExecutionTimeInMillis", 0) / 1000, 2),
    }
    print(row)
    if q["StatementType"] == "DML":
        key = q["ResultConfiguration"]["OutputLocation"].split(f"{BUCKET}/")[1]
        s3.download_file(BUCKET, key, str(OUT / f"{name}.csv"))
    return row


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = sys.argv[1:]
    run("CREATE DATABASE IF NOT EXISTS lab8", "00_database")
    rows = []
    for path in sorted((HERE / "sql").glob("*.sql")):
        if wanted and not any(path.stem.startswith(w) for w in wanted):
            continue
        sql = path.read_text()
        if "{table}" in sql:
            rows += [run(sql.format(table=t), f"{path.stem}_{fmt}") for fmt, t in TABLES.items()]
        else:
            rows.append(run(sql, path.stem))

    stats = OUT / "stats.csv"
    with stats.open("a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        if stats.stat().st_size == 0:
            writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
