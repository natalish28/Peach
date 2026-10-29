import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Agenda
from app.schemas import AgendaCreate

# Scoped to one owner, like items: someone else's agenda looks like a missing one.


async def list_agendas(
    session: AsyncSession, owner_id: uuid.UUID, *, limit: int, offset: int
) -> tuple[list[Agenda], int]:
    total = (
        await session.scalar(
            select(func.count()).select_from(Agenda).where(Agenda.owner_id == owner_id)
        )
        or 0
    )
    result = await session.execute(
        select(Agenda)
        .where(Agenda.owner_id == owner_id)
        .order_by(Agenda.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return list(result.scalars()), total


async def create_agenda(
    session: AsyncSession, owner_id: uuid.UUID, payload: AgendaCreate
) -> Agenda:
    data = payload.model_dump(mode="json", exclude={"starts_at"})
    agenda = Agenda(owner_id=owner_id, starts_at=payload.starts_at, **data)
    session.add(agenda)
    await session.flush()
    await session.refresh(agenda)
    return agenda
