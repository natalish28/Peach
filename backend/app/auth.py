import json
import logging
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select

from app.config import get_settings
from app.db import SessionDep
from app.models.user import User

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
        if settings.cognito_jwks:
            # Lambda execution in VPC: keys passed via environment
            jwks_data = json.loads(settings.cognito_jwks)
            signing_keys = {
                key["kid"]: jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key))
                for key in jwks_data.get("keys", [])
            }
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get("kid")
            if not kid or kid not in signing_keys:
                raise ValueError("Key ID not found in JWKS")
            key = signing_keys[kid]
            payload = jwt.decode(
                token,
                key=key,
                algorithms=["RS256"],
                audience=settings.cognito_client_id,
                issuer=settings.cognito_issuer,
                options={"verify_exp": True},
            )
        else:
            # Local / testing environment with internet access
            jwks_client = jwt.PyJWKClient(f"{settings.cognito_issuer}/.well-known/jwks.json")
            signing_key = jwks_client.get_signing_key_from_jwt(token)
            payload = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=settings.cognito_client_id,
                issuer=settings.cognito_issuer,
                options={"verify_exp": True},
            )

        if payload.get("token_use") != "id":
            raise ValueError("Token is not an ID token")

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
