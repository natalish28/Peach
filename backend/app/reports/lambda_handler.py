"""Lambda handler for the report-builder function.

Triggered either by:
1. SQS message from EventBridge Scheduler (source='schedule') or make report-now (source='sqs'/'manual')
2. Direct invocation with payload {"source": "schedule"} or {"week": "..."}

Queries database, produces CSV for the week, and uploads to S3.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import logging
import os
import sys

import boto3

from app.reports.weekly import build_weekly_report

# Configure logger
logger = logging.getLogger("report-builder")
logger.setLevel(logging.INFO)
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    logger.addHandler(handler)


def detect_trigger(event: dict) -> tuple[str, str | None]:
    """Detect whether triggered by schedule, SQS, or manual direct invocation."""
    records = event.get("Records")
    if records and isinstance(records, list) and len(records) > 0:
        first = records[0]
        if first.get("eventSource") == "aws:sqs":
            try:
                body = json.loads(first.get("body", "{}"))
                week = body.get("week")
                src = body.get("source", "")
                if src == "schedule":
                    return "schedule", week
                return "sqs", week
            except Exception:
                return "sqs", None

    src = event.get("source", "")
    if src in ("schedule", "aws.scheduler"):
        return "schedule", event.get("week")

    return "sqs" if "sqs" in src else "direct", event.get("week")


def get_default_week() -> str:
    """Return the previous ISO week string, e.g. '2026-W41'."""
    now = datetime.now(timezone.utc)
    prev = now - timedelta(days=7)
    return prev.strftime("%G-W%V")


def handler(event: dict, context: any) -> dict:
    """AWS Lambda entry point for report-builder."""
    trigger, week_override = detect_trigger(event)
    week = week_override or get_default_week()

    # Required CloudWatch log line
    logger.info(
        "report-builder triggered: trigger=%s week=%s event_source=%s",
        trigger,
        week,
        event.get("eventSource") or ("sqs" if "Records" in event else "direct"),
        extra={"trigger": trigger, "week": week},
    )

    # 1. Build CSV report
    logger.info("Building report for week %s...", week)
    csv_bytes = build_weekly_report(week)

    # 2. Upload to S3
    bucket_name = os.environ.get("REPORTS_BUCKET")
    if not bucket_name:
        raise ValueError("REPORTS_BUCKET environment variable is not set")

    key = f"reports/{week}.csv"
    logger.info("Uploading report to s3://%s/%s (%d bytes)...", bucket_name, key, len(csv_bytes))

    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=csv_bytes,
        ContentType="text/csv",
    )

    logger.info("Successfully uploaded report to s3://%s/%s", bucket_name, key)
    return {
        "statusCode": 200,
        "week": week,
        "trigger": trigger,
        "bucket": bucket_name,
        "key": key,
    }

