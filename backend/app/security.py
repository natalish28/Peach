"""Cognito ID-token verification, shared by the API and the agenda-parser function."""

import json
from functools import lru_cache
from typing import Any

import jwt

from app.config import Settings


@lru_cache
def _jwks_client(url: str) -> jwt.PyJWKClient:
    # One client per execution environment: it caches the pool's keys.
    return jwt.PyJWKClient(url)


def verify_id_token(token: str, settings: Settings) -> dict[str, Any]:
    """Return the claims of a valid Cognito ID token; raise on anything else.

    Keys come from COGNITO_JWKS when set (the VPC Lambda has no route to fetch
    them), otherwise they are downloaded from the issuer.
    """
    if settings.cognito_jwks:
        jwks_data = json.loads(settings.cognito_jwks)
        signing_keys = {
            key["kid"]: jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key))
            for key in jwks_data.get("keys", [])
        }
        kid = jwt.get_unverified_header(token).get("kid")
        if not kid or kid not in signing_keys:
            raise ValueError("Key ID not found in JWKS")
        key: Any = signing_keys[kid]
    else:
        key = (
            _jwks_client(f"{settings.cognito_issuer}/.well-known/jwks.json")
            .get_signing_key_from_jwt(token)
            .key
        )

    payload = jwt.decode(
        token,
        key=key,
        algorithms=["RS256"],
        audience=settings.cognito_client_id,
        issuer=settings.cognito_issuer,
        options={"verify_exp": True},
    )
    if payload.get("token_use") != "id":
        raise ValueError("Token is not an ID token")
    return payload
