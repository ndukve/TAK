import os

import asyncpg
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

POSTGRES_USER = os.environ["POSTGRES_USER"]
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]
POSTGRES_ADDRESS = os.environ.get("POSTGRES_ADDRESS", "takdb")

DATABASE_URL = (
    f"postgresql+asyncpg://{POSTGRES_USER}:{POSTGRES_PASSWORD}"
    f"@{POSTGRES_ADDRESS}:5432/admin"
)


async def ensure_database():
    """Create the 'admin' database if it doesn't exist."""
    conn = await asyncpg.connect(
        host=POSTGRES_ADDRESS,
        port=5432,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        database="postgres",
    )
    try:
        exists = await conn.fetchval(
            "SELECT 1 FROM pg_database WHERE datname = 'admin'"
        )
        if not exists:
            await conn.execute("CREATE DATABASE admin")
            print("[admin] Created 'admin' database", flush=True)
    finally:
        await conn.close()

engine = create_async_engine(DATABASE_URL, echo=False)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db():
    async with SessionLocal() as session:
        yield session
