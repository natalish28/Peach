from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.config import get_settings


class Base(DeclarativeBase):
    """Declarative base shared by every ORM model."""


import logging
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

logger = logging.getLogger(__name__)


def resolve_database_url(url: str, region: str = "us-east-1") -> str:
    """Resolve database URL with dynamic RDS IAM authentication token if needed."""
    parsed = urlsplit(url)
    if parsed.hostname and "rds.amazonaws.com" in parsed.hostname:
        try:
            import boto3

            client = boto3.client("rds", region_name=region)
            uname = parsed.username or "postgres"
            port = parsed.port or 5432
            token = client.generate_db_auth_token(
                DBHostname=parsed.hostname,
                Port=port,
                DBUsername=uname,
            )
            query = dict(parse_qsl(parsed.query))
            query["ssl"] = "require"
            netloc = f"{uname}:{token}@{parsed.hostname}:{port}"
            return urlunsplit((parsed.scheme, netloc, parsed.path, urlencode(query), parsed.fragment))
        except Exception as exc:
            logger.warning("Could not generate RDS IAM auth token: %s", exc)
    return url


from sqlalchemy import event


def create_engine() -> AsyncEngine:
    settings = get_settings()
    parsed = urlsplit(settings.database_url)
    is_rds = bool(parsed.hostname and "rds.amazonaws.com" in parsed.hostname)

    db_url = settings.database_url
    poolclass = NullPool if not settings.db_pooling else None
    eng = create_async_engine(
        db_url,
        echo=False,
        poolclass=poolclass,
        pool_pre_ping=settings.db_pooling,
    )

    if is_rds:
        @event.listens_for(eng.sync_engine, "do_connect")
        def rds_iam_connect(dialect, conn_rec, cargs, cparams):
            try:
                import boto3

                client = boto3.client("rds", region_name=settings.cognito_region)
                cparams["password"] = client.generate_db_auth_token(
                    DBHostname=cparams["host"],
                    Port=cparams.get("port", 5432),
                    DBUsername=cparams.get("user", "postgres"),
                )
                cparams["ssl"] = "require"
            except Exception as exc:
                logger.warning("RDS IAM auth in do_connect failed: %s", exc)

    return eng


engine: AsyncEngine = create_engine()
SessionFactory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency yielding a session that commits on success, rolls back on error."""
    async with SessionFactory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


SessionDep = Annotated[AsyncSession, Depends(get_session)]
