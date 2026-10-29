from typing import Annotated

from fastapi import APIRouter, Query, status

from app.auth import CurrentUser
from app.db import SessionDep
from app.schemas import AgendaCreate, AgendaList, AgendaRead
from app.services import agendas as agendas_service

router = APIRouter(prefix="/agendas", tags=["agendas"])


@router.get("", response_model=AgendaList, summary="List agendas")
async def list_agendas(
    session: SessionDep,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AgendaList:
    agendas, total = await agendas_service.list_agendas(
        session, user.id, limit=limit, offset=offset
    )
    return AgendaList(agendas=[AgendaRead.model_validate(a) for a in agendas], total=total)


@router.post("", response_model=AgendaRead, status_code=status.HTTP_201_CREATED)
async def create_agenda(
    payload: AgendaCreate,
    session: SessionDep,
    user: CurrentUser,
) -> AgendaRead:
    """Save an agenda. The only write path: the parser's suggestion arrives here
    as `ai_suggestion` and is validated like any other input."""
    agenda = await agendas_service.create_agenda(session, user.id, payload)
    return AgendaRead.model_validate(agenda)
