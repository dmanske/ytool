import asyncio
import subprocess
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from config import settings

router = APIRouter()


class ConfigUpdate(BaseModel):
    base_download_dir: str | None = None
    categories: list[str] | None = None


@router.get("")
async def get_config():
    return {
        "base_download_dir": str(settings.base_download_dir),
        "categories": settings.categories,
        "google_configured": bool(settings.google_client_id and settings.google_client_secret),
    }


@router.post("")
async def update_config(body: ConfigUpdate):
    if body.base_download_dir is not None:
        new_dir = Path(body.base_download_dir).expanduser()
        new_dir.mkdir(parents=True, exist_ok=True)
        settings.base_download_dir = new_dir

    if body.categories is not None:
        settings.categories = body.categories

    return {
        "base_download_dir": str(settings.base_download_dir),
        "categories": settings.categories,
    }


@router.post("/open-folder")
async def open_folder(body: dict):
    """Open a folder in the system file manager (macOS Finder)."""
    raw = body.get("path", "")
    if not raw:
        return JSONResponse({"error": "path is required"}, status_code=400)

    folder = Path(raw).expanduser().resolve()

    if not folder.exists():
        # Maybe a file path was passed — try the parent
        folder = folder.parent
    if not folder.exists():
        return JSONResponse({"error": "folder not found"}, status_code=404)

    if not folder.is_dir():
        folder = folder.parent

    await asyncio.to_thread(subprocess.run, ["open", str(folder)], check=False)
    return {"opened": str(folder)}
