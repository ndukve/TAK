"""TAK Server groups (ATAK shows them as channels): list who is in which, and change a user's groups.

TAK Server owns the data: `UserAuthenticationFile.xml` holds each certificate user's `groupList`, and `UserManager.jar certmod` is its own tool to
change it (the same one enable_user.sh uses). Nothing here edits that file by hand. A group has no record of its own: it exists once a user is put in it.
Direction follows TAK's words: "both" = send and receive (-g), "send" = the user may write to the group (-ig), "receive" = the user may read it (-og).
"""

import os
import re
import xml.etree.ElementTree as ET  # nosec B405 - input checked for DTD/entities below, written by TAK Server itself

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .deps import require_role, write_audit
from .docker_exec import run_in_container
from .users import TAK_DATA, TAK_USER_GROUP, _is_always_enabled, _validate_username

router = APIRouter(prefix="/api/groups", tags=["groups"])
_superadmin = require_role("superadmin")

USER_FILE = "/opt/tak/data/UserAuthenticationFile.xml"
_GROUP_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
_NS = "{http://bbn.com/marti/xml/bindings}"
# TAK keeps revoked certificates in this group (see the user file); assigning it here would silently revoke someone: use disable instead.
RESERVED = {"revoked"}


def parse_user_file(xml_text: str) -> list[dict]:
    """[{username, groups: [raw group names]}] from UserAuthenticationFile.xml (certificate users only; password hashes are never read)."""
    if "<!DOCTYPE" in xml_text or "<!ENTITY" in xml_text:
        raise ValueError("user file has a DTD or entity declaration; refusing to parse it")   # XXE / entity-expansion guard: TAK Server never writes one
    root = ET.fromstring(xml_text)
    users = []
    for user in root.iter(f"{_NS}User"):
        raw = (user.findtext(f"{_NS}groupList") or "").replace(",", " ")
        users.append({"username": user.get("identifier", ""), "groups": [g for g in raw.split() if g]})
    return users


def by_group(users: list[dict]) -> list[dict]:
    members: dict[str, list[str]] = {}
    for user in users:
        for group in user["groups"]:
            members.setdefault(group, []).append(user["username"])
    return [{"name": name, "members": sorted(names)} for name, names in sorted(members.items())]


def is_protected(username: str) -> bool:
    """Service accounts (EFDI's own feed among them) may only gain groups here, never lose or swap them."""
    return username.endswith("-Service") or _is_always_enabled(username)


class AssignRequest(BaseModel):
    username: str
    mode: str = Field(default="set", pattern="^(set|add|remove)$")
    both: list[str] = []
    send: list[str] = []
    receive: list[str] = []


def build_args(body: AssignRequest) -> list[str]:
    """The certmod arguments for a request; raises HTTPException(400/409) for anything not allowed."""
    username = _validate_username(body.username)
    names = body.both + body.send + body.receive
    if not names:
        raise HTTPException(status_code=400, detail="Name at least one group")
    for name in names:
        if not _GROUP_RE.fullmatch(name):
            raise HTTPException(status_code=400, detail=f"Group name {name!r}: letters, digits, '.', '_' and '-' only (max 64)")
        if name in RESERVED:
            raise HTTPException(status_code=400, detail=f"{name!r} is TAK's bucket for revoked certificates; disable the user instead")
    if is_protected(username) and body.mode != "add":
        raise HTTPException(status_code=409, detail=f"{username} is a service account: groups can only be added to it, not replaced or removed")
    args = {"set": [], "add": ["-a"], "remove": ["-r"]}[body.mode]
    for flag, groups in (("-g", body.both), ("-ig", body.send), ("-og", body.receive)):
        for group in groups:
            args += [flag, group]
    return args


@router.get("")
async def list_groups(_=Depends(require_role("admin", "superadmin"))):
    code, out = await run_in_container(["cat", USER_FILE])
    if code != 0:
        raise HTTPException(status_code=502, detail="Could not read TAK Server's user file")
    try:
        users = parse_user_file(out)
    except (ValueError, ET.ParseError) as exc:
        raise HTTPException(status_code=502, detail=f"TAK Server's user file could not be read: {exc}") from exc
    return {"groups": by_group(users), "users": users, "default_group": TAK_USER_GROUP}


@router.post("/assign")
async def assign_groups(body: AssignRequest, db: AsyncSession = Depends(get_db), actor=Depends(_superadmin)):
    username = _validate_username(body.username)
    args = build_args(body)
    pem = os.path.join(TAK_DATA, f"{username}.pem")
    if not os.path.isfile(pem):
        raise HTTPException(status_code=404, detail="No certificate with that name exists")
    # Same environment enable_user.sh uses; the values travel as arguments, never inside the shell text.
    code, out = await run_in_container(
        ["bash", "-c", 'cd /opt/tak && . ./setenv.sh >/dev/null 2>&1; '
                       'TAKCL_CORECONFIG_PATH=/opt/tak/data/CoreConfig.xml exec java -jar utils/UserManager.jar certmod "$@"',
         "_", *args, pem],
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=out)
    await write_audit(db, actor.id, "set_user_groups", f"{username} {body.mode} both={body.both} send={body.send} receive={body.receive}")
    return {"status": "ok", "output": out}
