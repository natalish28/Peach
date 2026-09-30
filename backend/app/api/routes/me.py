from fastapi import APIRouter

from app.auth import CurrentUser
from app.schemas.user import UserRead

router = APIRouter(tags=["me"])


@router.get("/me", response_model=UserRead, summary="Current user")
async def get_me(user: CurrentUser) -> UserRead:
    return UserRead.model_validate(user)
