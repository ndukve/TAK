import os
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

app = FastAPI(title="TAK Admin API", version="1.0.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


# Static files mounted after API routes (frontend build)
UI_DIR = os.path.join(os.path.dirname(__file__), "..", "ui", "dist")
if os.path.isdir(UI_DIR):
    app.mount("/", StaticFiles(directory=UI_DIR, html=True), name="ui")
