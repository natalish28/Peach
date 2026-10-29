import logging
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select

from app.config import get_settings
from app.db import SessionDep
from app.models.user import User
from app.security import verify_id_token

logger = logging.getLogger(__name__)


async def current_user(
    request: Request,
    session: SessionDep,
) -> User:
    """Validate Cognito ID token from Authorization header and return the User instance."""
    settings = get_settings()

    # Public liveness and documentation endpoints do not require auth
    if request.url.path in ("/health", "/docs", "/redoc", "/openapi.json"):
        # Dummy or placeholder if invoked directly on these routes
        return User(cognito_sub="public", email="public@example.com")

    if not settings.auth_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication is not configured",
        )

    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = auth_header[7:].strip()

    try:
        payload = verify_id_token(token, settings)
    except Exception as exc:
        logger.warning("Token verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    sub = payload["sub"]
    email = payload.get("email", "")
    name = payload.get("name") or payload.get("cognito:username")

    user = await session.scalar(select(User).where(User.cognito_sub == sub))
    if user is None:
        user = User(cognito_sub=sub, email=email, name=name)
        session.add(user)
        await session.flush()
        await session.refresh(user)

    return user


CurrentUser = Annotated[User, Depends(current_user)]
