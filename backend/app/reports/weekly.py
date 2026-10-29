"""Weekly report builder.

Generates a CSV report summarizing tasks and user activity for a given ISO week.
"""

from __future__ import annotations

import asyncio
import csv
import io
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.db import create_engine
from app.models.item import Item
from app.models.user import User


def parse_iso_week(week_str: str) -> tuple[datetime, datetime]:
    """Parse an ISO week string like '2026-W41' into UTC start and end datetimes."""
    # %G = ISO 4-digit year, %V = ISO week number, %u = ISO weekday (1=Monday)
    start = datetime.strptime(f"{week_str}-1", "%G-W%V-%u").replace(
        hour=0, minute=0, second=0, microsecond=0, tzinfo=UTC
    )
    end = start + timedelta(days=7)
    return start, end


async def _build_weekly_report_async(week: str) -> bytes:
    current_start, current_end = parse_iso_week(week)
    prev_start = current_start - timedelta(days=7)
    prev_end = current_start

    engine = create_engine()
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with session_factory() as session:
            # 1. Total items created in current week
            res_current_created = await session.execute(
                select(func.count(Item.id)).where(
                    and_(Item.created_at >= current_start, Item.created_at < current_end)
                )
            )
            current_created_count = res_current_created.scalar() or 0

            # Total items completed in current week
            res_current_done = await session.execute(
                select(func.count(Item.id)).where(
                    and_(
                        Item.status == "done",
                        Item.updated_at >= current_start,
                        Item.updated_at < current_end,
                    )
                )
            )
            current_done_count = res_current_done.scalar() or 0

            # 2. Total items created in previous week
            res_prev_created = await session.execute(
                select(func.count(Item.id)).where(
                    and_(Item.created_at >= prev_start, Item.created_at < prev_end)
                )
            )
            prev_created_count = res_prev_created.scalar() or 0

            # Total items completed in previous week
            res_prev_done = await session.execute(
                select(func.count(Item.id)).where(
                    and_(
                        Item.status == "done",
                        Item.updated_at >= prev_start,
                        Item.updated_at < prev_end,
                    )
                )
            )
            prev_done_count = res_prev_done.scalar() or 0

            # Breakdown by status in current week
            res_status = await session.execute(
                select(Item.status, func.count(Item.id))
                .where(and_(Item.created_at >= current_start, Item.created_at < current_end))
                .group_by(Item.status)
            )
            status_counts = dict(res_status.all())

            # Breakdown per user
            res_users = await session.execute(
                select(
                    User.name,
                    User.email,
                    func.count(Item.id).label("total_items"),
                    func.count(func.nullif(Item.status != "todo", True)).label("todo_count"),
                    func.count(func.nullif(Item.status != "in_progress", True)).label(
                        "in_progress_count"
                    ),
                    func.count(func.nullif(Item.status != "done", True)).label("done_count"),
                )
                .join(Item, Item.owner_id == User.id)
                .where(and_(Item.created_at >= current_start, Item.created_at < current_end))
                .group_by(User.id, User.name, User.email)
            )
            user_rows = res_users.all()

            # Detailed list of tasks in current week (up to 100)
            res_tasks = await session.execute(
                select(Item, User.name, User.email)
                .join(User, Item.owner_id == User.id, isouter=True)
                .where(and_(Item.created_at >= current_start, Item.created_at < current_end))
                .order_by(Item.created_at.desc())
                .limit(100)
            )
            task_rows = res_tasks.all()

        output = io.StringIO()
        writer = csv.writer(output)

        writer.writerow(["# WEEKLY REPORT", week])
        writer.writerow(["# Period Start (UTC)", current_start.strftime("%Y-%m-%d %H:%M:%S")])
        writer.writerow(
            [
                "# Period End (UTC)",
                (current_end - timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S"),
            ]
        )
        writer.writerow([])

        # Summary Metrics
        created_change = current_created_count - prev_created_count
        done_change = current_done_count - prev_done_count
        writer.writerow(["METRIC", "CURRENT_WEEK", "PREVIOUS_WEEK", "CHANGE"])
        writer.writerow(
            ["Tasks Created", current_created_count, prev_created_count, f"{created_change:+d}"]
        )
        writer.writerow(
            ["Tasks Completed", current_done_count, prev_done_count, f"{done_change:+d}"]
        )
        writer.writerow(["Tasks To Do", status_counts.get("todo", 0), "-", "-"])
        writer.writerow(["Tasks In Progress", status_counts.get("in_progress", 0), "-", "-"])
        writer.writerow([])

        # User breakdown
        writer.writerow(["USER SUMMARY"])
        writer.writerow(["Name", "Email", "Total Tasks", "Todo", "In Progress", "Done"])
        if user_rows:
            for r in user_rows:
                writer.writerow(
                    [
                        r.name,
                        r.email,
                        r.total_items,
                        r.todo_count,
                        r.in_progress_count,
                        r.done_count,
                    ]
                )
        else:
            writer.writerow(["No user activity recorded for this week", "", "", "", "", ""])
        writer.writerow([])

        # Tasks detail
        writer.writerow(["TASKS DETAIL"])
        writer.writerow(
            [
                "Task ID",
                "Title",
                "Status",
                "Owner Name",
                "Owner Email",
                "Created At (UTC)",
                "Updated At (UTC)",
            ]
        )
        if task_rows:
            for item, u_name, u_email in task_rows:
                writer.writerow(
                    [
                        str(item.id),
                        item.name,
                        item.status,
                        u_name or "Unknown",
                        u_email or "",
                        item.created_at.strftime("%Y-%m-%d %H:%M:%S") if item.created_at else "",
                        item.updated_at.strftime("%Y-%m-%d %H:%M:%S") if item.updated_at else "",
                    ]
                )
        else:
            writer.writerow(["No tasks created in this period", "", "", "", "", "", ""])

        return output.getvalue().encode("utf-8")
    finally:
        await engine.dispose()


def build_weekly_report(week: str) -> bytes:
    """Query tasks of one ISO week (e.g. '2026-W41') and return CSV bytes."""
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if loop and loop.is_running():
        # In case called inside an already running event loop
        import concurrent.futures

        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            return pool.submit(asyncio.run, _build_weekly_report_async(week)).result()
    else:
        return asyncio.run(_build_weekly_report_async(week))
