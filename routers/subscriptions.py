import asyncio
import csv
import io
import json

from fastapi import APIRouter, File, Query, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, StreamingResponse
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build

from services.youtube_auth import (
    add_video_to_playlist,
    create_flow,
    create_playlist,
    delete_credentials,
    get_credentials,
    list_playlist_items,
    list_playlists,
    list_subscriptions,
    save_credentials,
    subscribe_to_channel,
)

router = APIRouter()

# In-process OAuth state: account_key -> Flow
_pending_flows: dict[str, Flow] = {}

_OAUTH_DONE_HTML = """<!DOCTYPE html>
<html>
<head><title>YTool — Authorized</title></head>
<body>
<script>
  if (window.opener) {
    window.opener.postMessage('oauth_done', '*');
    window.close();
  } else {
    document.write('<p>Authorized! You can close this tab.</p>');
  }
</script>
</body>
</html>"""


@router.get("/oauth/start")
async def oauth_start(account_key: str = Query(...)):
    flow = create_flow()
    auth_url, _ = flow.authorization_url(
        prompt="select_account consent",
        access_type="offline",
    )
    _pending_flows[account_key] = flow
    return RedirectResponse(auth_url)


@router.get("/oauth/callback")
async def oauth_callback(code: str, state: str | None = None, account_key: str | None = None):
    # account_key may come as a query param (set via redirect_uri) or state
    key = account_key or state
    flow = _pending_flows.pop(key, None)
    if not flow:
        return JSONResponse({"error": "no pending OAuth flow for this account"}, status_code=400)
    await asyncio.to_thread(flow.fetch_token, code=code)
    await save_credentials(key, flow.credentials)
    return HTMLResponse(_OAUTH_DONE_HTML)


@router.get("/status")
async def oauth_status(account_key: str = Query(...)):
    creds = await get_credentials(account_key)
    return {"account_key": account_key, "authenticated": creds is not None}


@router.post("/logout")
async def oauth_logout(account_key: str = Query(...)):
    await delete_credentials(account_key)
    return {"account_key": account_key, "logged_out": True}


@router.get("/export")
async def export_subscriptions(
    account_key: str = Query("source"),
    fmt: str = Query("json"),
):
    creds = await get_credentials(account_key)
    if not creds:
        return JSONResponse({"error": "not authenticated"}, status_code=401)

    subs = await asyncio.to_thread(list_subscriptions, creds)

    if fmt == "csv":
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=["channel_id", "title"])
        writer.writeheader()
        writer.writerows(subs)
        return StreamingResponse(
            io.BytesIO(buf.getvalue().encode()),
            media_type="text/csv",
            headers={"Content-Disposition": "attachment; filename=subscriptions.csv"},
        )

    content = json.dumps(subs, ensure_ascii=False, indent=2).encode()
    return StreamingResponse(
        io.BytesIO(content),
        media_type="application/json",
        headers={"Content-Disposition": "attachment; filename=subscriptions.json"},
    )


@router.post("/import")
async def import_subscriptions(
    account_key: str = Query("dest"),
    file: UploadFile = File(...),
):
    content = await file.read()

    if file.filename and file.filename.endswith(".csv"):
        reader = csv.DictReader(io.StringIO(content.decode()))
        channels = [{"channel_id": row["channel_id"], "title": row.get("title", "")} for row in reader]
    else:
        channels = json.loads(content)

    async def stream():
        creds = await get_credentials(account_key)
        if not creds:
            yield f"data: {json.dumps({'status': 'error', 'message': 'not authenticated'})}\n\n"
            return

        youtube = build("youtube", "v3", credentials=creds)
        total = len(channels)

        for i, ch in enumerate(channels):
            cid = ch["channel_id"]
            title = ch.get("title", cid)
            try:
                await asyncio.to_thread(subscribe_to_channel, youtube, cid)
                yield f"data: {json.dumps({'status': 'progress', 'done': i + 1, 'total': total, 'title': title})}\n\n"
            except Exception as e:
                yield f"data: {json.dumps({'status': 'error', 'title': title, 'message': str(e)})}\n\n"
            await asyncio.sleep(1.0)

        yield f"data: {json.dumps({'status': 'done', 'total': total})}\n\n"

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/transfer")
async def transfer_subscriptions(
    source_key: str = Query("source"),
    dest_key: str = Query("dest"),
):
    async def stream():
        src_creds = await get_credentials(source_key)
        if not src_creds:
            yield f"data: {json.dumps({'status': 'error', 'message': 'source account not authenticated'})}\n\n"
            return

        dest_creds = await get_credentials(dest_key)
        if not dest_creds:
            yield f"data: {json.dumps({'status': 'error', 'message': 'destination account not authenticated'})}\n\n"
            return

        yield f"data: {json.dumps({'status': 'log', 'message': 'Fetching subscriptions from source account...'})}\n\n"
        channels = await asyncio.to_thread(list_subscriptions, src_creds)
        total = len(channels)
        yield f"data: {json.dumps({'status': 'log', 'message': f'Found {total} subscriptions. Starting transfer...'})}\n\n"

        youtube_dest = build("youtube", "v3", credentials=dest_creds)

        for i, ch in enumerate(channels):
            cid = ch["channel_id"]
            title = ch["title"]
            try:
                await asyncio.to_thread(subscribe_to_channel, youtube_dest, cid)
                yield f"data: {json.dumps({'status': 'progress', 'done': i + 1, 'total': total, 'title': title})}\n\n"
            except Exception as e:
                yield f"data: {json.dumps({'status': 'error', 'title': title, 'message': str(e)})}\n\n"
            await asyncio.sleep(1.0)

        yield f"data: {json.dumps({'status': 'done', 'total': total})}\n\n"

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ── Playlists ──────────────────────────────────────────────────────────────────

@router.get("/playlists")
async def get_playlists(account_key: str = Query("source")):
    """List all playlists (public + private) for the given account."""
    creds = await get_credentials(account_key)
    if not creds:
        return JSONResponse({"error": "not authenticated"}, status_code=401)
    playlists = await asyncio.to_thread(list_playlists, creds)
    return {"playlists": playlists}


@router.post("/playlists/transfer")
async def transfer_playlists(
    source_key: str = Query("source"),
    dest_key: str = Query("dest"),
    playlist_ids: list[str] = [],
):
    """Transfer selected playlists from source to dest account, streaming SSE progress."""

    async def stream():
        src_creds = await get_credentials(source_key)
        if not src_creds:
            yield f"data: {json.dumps({'status': 'error', 'message': 'source account not authenticated'})}\n\n"
            return

        dest_creds = await get_credentials(dest_key)
        if not dest_creds:
            yield f"data: {json.dumps({'status': 'error', 'message': 'destination account not authenticated'})}\n\n"
            return

        # Fetch all playlists from source, filter to selected ones
        all_playlists = await asyncio.to_thread(list_playlists, src_creds)
        selected = [p for p in all_playlists if p["playlist_id"] in playlist_ids] if playlist_ids else all_playlists

        if not selected:
            yield f"data: {json.dumps({'status': 'error', 'message': 'No playlists selected or found'})}\n\n"
            return

        youtube_src = build("youtube", "v3", credentials=src_creds)
        youtube_dest = build("youtube", "v3", credentials=dest_creds)

        total_playlists = len(selected)
        yield f"data: {json.dumps({'status': 'log', 'message': f'Transferring {total_playlists} playlist(s)...'})}\n\n"

        for pl_idx, playlist in enumerate(selected):
            pl_title = playlist["title"]
            pl_id = playlist["playlist_id"]

            yield f"data: {json.dumps({'status': 'playlist_start', 'playlist_index': pl_idx + 1, 'playlist_total': total_playlists, 'playlist_title': pl_title})}\n\n"

            # Fetch all videos in this playlist
            try:
                items = await asyncio.to_thread(list_playlist_items, youtube_src, pl_id)
            except Exception as e:
                yield f"data: {json.dumps({'status': 'error', 'message': f'Failed to read playlist \"{pl_title}\": {str(e)}'})}\n\n"
                continue

            total_videos = len(items)
            yield f"data: {json.dumps({'status': 'log', 'message': f'Playlist \"{pl_title}\" has {total_videos} video(s). Creating on destination...'})}\n\n"

            # Create the playlist on destination
            try:
                new_pl_id = await asyncio.to_thread(
                    create_playlist,
                    youtube_dest,
                    playlist["title"],
                    playlist["description"],
                    playlist["privacy"],
                )
            except Exception as e:
                yield f"data: {json.dumps({'status': 'error', 'message': f'Failed to create playlist \"{pl_title}\": {str(e)}'})}\n\n"
                continue

            # Add each video
            for v_idx, video in enumerate(items):
                vid = video["video_id"]
                vtitle = video["title"]
                try:
                    await asyncio.to_thread(add_video_to_playlist, youtube_dest, new_pl_id, vid)
                except Exception as e:
                    yield f"data: {json.dumps({'status': 'error', 'title': vtitle, 'message': str(e)})}\n\n"

                yield f"data: {json.dumps({'status': 'progress', 'playlist_index': pl_idx + 1, 'playlist_total': total_playlists, 'playlist_title': pl_title, 'done': v_idx + 1, 'total': total_videos, 'title': vtitle})}\n\n"
                # Small delay to respect API rate limits
                await asyncio.sleep(0.3)

        yield f"data: {json.dumps({'status': 'done', 'total': total_playlists})}\n\n"

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
