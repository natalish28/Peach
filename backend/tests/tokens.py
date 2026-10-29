"""Signing key and tokens for tests.

Importing this module points the app at a throwaway Cognito pool whose public key
is the one generated here, so tests can sign in without touching AWS. conftest.py
imports it before `app` so the settings are read after the environment is set.
"""

import json
import os
import time

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

POOL_ID = "us-east-1_testpool"
CLIENT_ID = "test-client-id"
REGION = "us-east-1"
KID = "test-key"
ISSUER = f"https://cognito-idp.{REGION}.amazonaws.com/{POOL_ID}"

_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(_private_key.public_key()))
_jwk.update({"kid": KID, "alg": "RS256", "use": "sig"})

os.environ["COGNITO_REGION"] = REGION
os.environ["COGNITO_USER_POOL_ID"] = POOL_ID
os.environ["COGNITO_CLIENT_ID"] = CLIENT_ID
os.environ["COGNITO_JWKS"] = json.dumps({"keys": [_jwk]})


def make_token(sub: str = "alice-sub", email: str = "alice@example.com", **claims) -> str:
    now = int(time.time())
    payload = {
        "sub": sub,
        "email": email,
        "token_use": "id",
        "aud": CLIENT_ID,
        "iss": ISSUER,
        "iat": now,
        "exp": now + 3600,
        **claims,
    }
    return jwt.encode(payload, _private_key, algorithm="RS256", headers={"kid": KID})


def auth(sub: str = "alice-sub", email: str = "alice@example.com") -> dict[str, str]:
    return {"Authorization": f"Bearer {make_token(sub, email)}"}
