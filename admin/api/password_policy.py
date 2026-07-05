import hashlib
import os
import re

import httpx
from fastapi import HTTPException

# TAK deployments are frequently on air-gapped/tactical networks — an
# unexpected outbound call to api.pwnedpasswords.com on every password change
# could be a surprise there. Enabled by default (unchanged behavior for
# normal internet-connected installs); set ADMIN_HIBP_CHECK=0 to disable
# for air-gapped deployments.
_HIBP_ENABLED = os.environ.get("ADMIN_HIBP_CHECK", "1") != "0"

_RULES = [
    (r'[A-Z]', "at least one uppercase letter"),
    (r'[a-z]', "at least one lowercase letter"),
    (r'\d',    "at least one digit"),
    (r'[^A-Za-z0-9]', "at least one special character"),
]


def _complexity_error(password: str) -> str | None:
    if len(password) < 12:
        return "Password must be at least 12 characters"
    for pattern, msg in _RULES:
        if not re.search(pattern, password):
            return f"Password must contain {msg}"
    return None


async def _hibp_pwned(password: str) -> int:
    """Returns breach count via k-anonymity. 0 on network failure (fail open)."""
    sha1 = hashlib.sha1(password.encode("utf-8")).hexdigest().upper()
    prefix, suffix = sha1[:5], sha1[5:]
    try:
        async with httpx.AsyncClient(timeout=4) as client:
            r = await client.get(
                f"https://api.pwnedpasswords.com/range/{prefix}",
                headers={"Add-Padding": "true"},
            )
        for line in r.text.splitlines():
            h, _, count = line.partition(":")
            if h == suffix:
                return int(count)
    except Exception:
        pass
    return 0


async def validate_password(password: str) -> None:
    """Raises HTTPException 400 if password fails complexity or is in breach database."""
    err = _complexity_error(password)
    if err:
        raise HTTPException(status_code=400, detail=err)
    count = await _hibp_pwned(password)
    if count > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Password has appeared in {count:,} data breaches. Choose a different password.",
        )
