import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.types import Scope

from .db import engine, Base, ensure_database
from . import models  # noqa: F401 — ensures models register with Base
from .auth import router as auth_router, _ensure_first_user
from .admin_users import router as admin_users_router
from .users import router as users_router
from .health import router as health_router
from .packages import router as packages_router
from .logs import router as logs_router
from .shell import router as shell_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await ensure_database()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _ensure_first_user()
    yield


app = FastAPI(title="TAK Admin API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],  # dev only; prod serves from same origin
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

class SPAStaticFiles(StaticFiles):
    """Fall back to index.html for unknown paths (e.g. /logs, /users) so the
    client-side router can take over on direct navigation, refresh, or the
    browser back/forward buttons — otherwise Starlette's default 404 for a
    missing static file shows up as a raw JSON error page."""

    async def get_response(self, path: str, scope: Scope):
        response = await super().get_response(path, scope)
        if response.status_code == 404:
            response = await super().get_response("index.html", scope)
        return response


STATIC_DIR = "/app/static"
if os.path.isdir(STATIC_DIR):
    app.mount("/", SPAStaticFiles(directory=STATIC_DIR, html=True), name="static")
