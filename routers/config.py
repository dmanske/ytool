import asyncio
import platform
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


class OpenFolderRequest(BaseModel):
    path: str


@router.post("/open-folder")
async def open_folder(body: OpenFolderRequest):
    """Open a folder in the system file manager (macOS Finder)."""
    folder = Path(body.path).expanduser().resolve()

    if not folder.exists():
        # Maybe a file path was passed — try the parent
        folder = folder.parent
    if not folder.exists():
        return JSONResponse({"error": "folder not found"}, status_code=404)

    if not folder.is_dir():
        folder = folder.parent

    # Cross-platform: macOS=open, Windows=explorer, Linux=xdg-open
    system = platform.system()
    if system == "Darwin":
        cmd = ["open", str(folder)]
    elif system == "Windows":
        cmd = ["explorer", str(folder)]
    else:
        cmd = ["xdg-open", str(folder)]

    await asyncio.to_thread(subprocess.run, cmd, check=False)
    return {"opened": str(folder)}
