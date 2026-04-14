import httpx

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse, Response
from pydantic import BaseModel

from services.ytdlp_service import download_with_progress, get_formats

router = APIRouter()


class DownloadRequest(BaseModel):
    url: str
    format_id: str | None = None    # specific format id from inspect (overrides quality/format)
    format_kind: str | None = None  # "video+audio", "video", or "audio" — used to decide merging
    quality: str = "best"
    format: str = "mp4"
    audio_only: bool = False
    category: str = "Other"
    subtitles: bool = False
    sub_langs: str = "en,pt"       # comma-separated language codes, e.g. "en,pt,es"
    filename: str = ""             # custom filename without extension; empty = use video title


@router.get("/formats")
async def list_formats(url: str = Query(...)):
    return await get_formats(url)


@router.get("/thumbnail")
async def proxy_thumbnail(url: str = Query(...)):
    """Proxy thumbnail images to avoid CORS issues in the browser."""
    async with httpx.AsyncClient(follow_redirects=True, timeout=10) as client:
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
    return Response(content=resp.content, media_type=resp.headers.get("content-type", "image/jpeg"))


@router.post("/download")
async def start_download(req: DownloadRequest):
    return StreamingResponse(
        download_with_progress(
            url=req.url,
            format_id=req.format_id,
            format_kind=req.format_kind,
            quality=req.quality,
            fmt=req.format,
            audio_only=req.audio_only,
            category=req.category,
            subtitles=req.subtitles,
            sub_langs=req.sub_langs,
            filename=req.filename,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
