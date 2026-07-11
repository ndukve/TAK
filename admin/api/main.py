import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from starlette.exceptions import HTTPException
from starlette.types import Scope

from . import models  # noqa: F401 — ensures models register with Base
from .admin_users import router as admin_users_router
from .audit import router as audit_router
from .auth import _ensure_first_user
from .auth import router as auth_router
from .branding import router as branding_router
from .db import Base, engine, ensure_database
from .health import router as health_router
from .live_map import router as live_map_router
from .logs import router as logs_router
from .packages import router as packages_router
from .replay import router as replay_router
from .shell import router as shell_router
from .users import router as users_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await ensure_database()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text(
            "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS owned_callsign VARCHAR(64)"
        ))
        await conn.execute(text(
            "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"
        ))
        await conn.execute(text(
            "ALTER TABLE brand_settings ADD COLUMN IF NOT EXISTS logo_filename VARCHAR(128)"
        ))
    await _ensure_first_user()
    yield


app = FastAPI(title="TAK Admin API", version="1.0.5", lifespan=lifespan)

# Prod serves the UI from the same origin (via admin_proxy) — no CORS needed
# there at all. Only wire up the middleware when explicitly running the Vite
# dev server against this API, so a stray dev origin never ships in prod.
_dev_origin = os.environ.get("ADMIN_DEV_CORS_ORIGIN")
if _dev_origin:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[_dev_origin],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(auth_router)
app.include_router(admin_users_router)
app.include_router(users_router)
app.include_router(health_router)
app.include_router(packages_router)
app.include_router(logs_router)
app.include_router(shell_router)
app.include_router(audit_router)
app.include_router(branding_router)
app.include_router(replay_router)
app.include_router(live_map_router)

class SPAStaticFiles(StaticFiles):
    """Fall back to index.html for unknown client-side routes (e.g. /logs,
    /users) so the router can take over on direct navigation, refresh, or the
    browser back/forward buttons — otherwise Starlette's default 404 for a
    missing static file shows up as a raw JSON error page.

    Only falls back for extensionless paths (routes), not for paths that look
    like a real asset (e.g. a hashed JS chunk) — a genuinely missing asset
    should still 404 rather than silently serve HTML the browser then tries
    to parse as JS, which just turns a clear error into a confusing one."""

    async def get_response(self, path: str, scope: Scope):
        try:
            return await super().get_response(path, scope)
        except HTTPException as exc:
            if exc.status_code == 404 and "." not in path.rsplit("/", 1)[-1]:
                return await super().get_response("index.html", scope)
            raise


STATIC_DIR = "/app/static"
if os.path.isdir(STATIC_DIR):
    app.mount("/", SPAStaticFiles(directory=STATIC_DIR, html=True), name="static")
