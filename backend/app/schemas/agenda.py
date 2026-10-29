import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class AgendaItemIn(BaseModel):
    topic: str = Field(min_length=1, max_length=300)
    owner: str | None = Field(default=None, max_length=200)
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItemIn(BaseModel):
    task: str = Field(min_length=1, max_length=300)
    owner: str | None = Field(default=None, max_length=200)
    due: date | None = None


class AiSuggestion(BaseModel):
    """What the parser returned, kept verbatim next to the final agenda."""

    agenda: dict
    model: str = Field(max_length=100)
    prompt_version: str = Field(max_length=50)


class AgendaCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    starts_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=600)
    items: list[AgendaItemIn] = Field(min_length=1, max_length=50)
    action_items: list[ActionItemIn] = Field(default_factory=list, max_length=50)
    notes: str | None = Field(default=None, max_length=2000)
    ai_suggestion: AiSuggestion | None = None


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    starts_at: datetime | None
    duration_minutes: int | None
    items: list[AgendaItemIn]
    action_items: list[ActionItemIn]
    notes: str | None
    ai_suggestion: AiSuggestion | None
    created_at: datetime


class AgendaList(BaseModel):
    agendas: list[AgendaRead]
    total: int
