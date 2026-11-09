"""Firebase ID-token verification for the API.

Production is fail-closed: set PLANT_REQUIRE_AUTH=true (the default) and make
Google application credentials available only on the API server.  Local demos
may explicitly set PLANT_REQUIRE_AUTH=false; that setting must never be used
for a public deployment.
"""

from __future__ import annotations

import os
from functools import lru_cache
from typing import Any, Optional

from fastapi import Header, HTTPException


def auth_required() -> bool:
    return os.getenv("PLANT_REQUIRE_AUTH", "true").strip().casefold() not in {
        "0",
        "false",
        "no",
    }


@lru_cache(maxsize=1)
def _firebase_auth() -> Any:
    try:
        import firebase_admin
        from firebase_admin import auth

        if not firebase_admin._apps:  # Firebase Admin loads server credentials.
            firebase_admin.initialize_app()
        return auth
    except Exception as error:  # Configuration details must not leak to clients.
        raise HTTPException(
            status_code=503,
            detail="Secure API authentication is not configured on this server.",
        ) from error


def verified_user(authorization: Optional[str] = Header(default=None)) -> str:
    """Return Firebase UID after verifying a bearer token, or reject access."""
    if not auth_required():
        return "local-development"
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="A Firebase ID token is required.")
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail="A Firebase ID token is required.")
    try:
        decoded = _firebase_auth().verify_id_token(token, check_revoked=True)
        uid = decoded.get("uid")
        if not isinstance(uid, str) or not uid:
            raise ValueError("Missing token subject")
        if decoded.get("email_verified") is not True:
            raise HTTPException(status_code=403, detail="Verify your email before using the API.")
        return uid
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=401, detail="Session is invalid or expired.") from error
