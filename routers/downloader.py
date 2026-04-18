import json
import uuid
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, Query
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from services.history_service import clear_history, load_history, save_entry
from services.ytdlp_service import cancel_download, download_with_progress, get_formats

router = APIRouter()


class DownloadRequest(BaseModel):
    url: str
    format_id: str | None = None
    format_kind: str | None = None
    quality: str = "best"
    format: str = "mp4"
    audio_only: bool = False
    category: str = "Other"
    subtitles: bool = False
    sub_langs: str = "en,pt"
    filename: str = ""
    download_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    trim_start: str | None = None
    trim_end: str | None = None
    thumbnail: str = ""


class CancelRequest(BaseModel):
    download_id: str


@router.get("/formats")
async def list_formats(url: str = Query(...)):
    return await get_formats(url)


@router.get("/thumbnail")
async def proxy_thumbnail(url: str = Query(...)):
    """Proxy thumbnail images to avoid CORS issues in the browser."""
    async with httpx.AsyncClient(follow_redirects=True, timeout=10) as client:
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
    return Response(content=resp.content, media_type=resp.headers.get("content-type", "image/jpeg"))


@router.get("/history")
async def get_history():
    return await load_history()


@router.delete("/history")
async def delete_history():
    await clear_history()
    return {"cleared": True}


@router.post("/download/cancel")
async def cancel(req: CancelRequest):
    cancelled = await cancel_download(req.download_id)
    return {"cancelled": cancelled, "download_id": req.download_id}


@router.post("/download")
async def start_download(req: DownloadRequest):
    async def stream_and_record():
        output_dir = ""
        async for chunk in download_with_progress(
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
            download_id=req.download_id,
            trim_start=req.trim_start,
            trim_end=req.trim_end,
        ):
            # Capture output_dir from the done event for history
            if '"status": "done"' in chunk:
                try:
                    payload = json.loads(chunk.removeprefix("data: ").strip())
                    output_dir = payload.get("output_dir", "")
                except Exception:
                    pass
            yield chunk

        # Save to history on successful completion
        if output_dir:
            await save_entry({
                "url": req.url,
                "title": req.filename or "",
                "output_dir": output_dir,
                "thumbnail": req.thumbnail,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "category": req.category,
            })

    return StreamingResponse(
        stream_and_record(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
