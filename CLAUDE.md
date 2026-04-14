# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**YTool** — Local web app with two modules:
1. **Downloader** — YouTube and Instagram videos/photos via `yt-dlp`
2. **Subscriptions** — Export, import, and transfer YouTube subscriptions between accounts via OAuth

See [DESIGN.md](DESIGN.md) for full architecture decisions and rationale.

## Stack

- **Python 3.12+** managed with `uv`
- **FastAPI** + uvicorn for the backend
- **yt-dlp** called via `asyncio.subprocess` (non-blocking)
- **Google OAuth** via `google-auth-oauthlib` + `google-api-python-client`
- **SSE (Server-Sent Events)** for real-time download/transfer progress
- **HTML/CSS/JS vanilla** + Tailwind via CDN (no build step)

## Commands

```bash
# Install dependencies
uv sync

# Run dev server (opens localhost:8000 automatically in browser)
uv run python app.py

# Run tests
uv run pytest

# Run single test
uv run pytest tests/test_ytdlp_service.py::test_name

# Lint
uv run ruff check .
uv run ruff format .
```

## Architecture

```
routers/        # HTTP layer only — no business logic here
services/       # All business logic
  ytdlp_service.py    # Calls yt-dlp via asyncio.subprocess, streams SSE progress
  youtube_auth.py     # OAuth flow + subscription list/subscribe operations
static/         # Single-page UI with three tabs: Downloads, Subscriptions, Config
config.py       # Base download dir, saved categories, credential paths
```

**Key patterns:**
- Downloads and subscription transfers stream progress via SSE — always use `StreamingResponse` with `text/event-stream`
- yt-dlp is called as a subprocess, never imported directly, to avoid blocking the event loop
- OAuth tokens are stored in `~/.ytool/tokens/` (outside the repo)
- Download output path is always `{base_dir}/{platform}/{category}/` where platform is auto-detected from the URL
- Subscription import/transfer subscribes at ~1 req/second to respect YouTube API rate limits

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/download` | Start download (streams SSE progress) |
| GET | `/api/subscriptions/export` | Export subscriptions as JSON or CSV |
| POST | `/api/subscriptions/import` | Import subscriptions from file (streams SSE) |
| POST | `/api/subscriptions/transfer` | Transfer directly between two accounts (streams SSE) |

`DownloadRequest` fields: `url`, `quality` (best/1080p/720p/480p/360p), `format` (mp4/webm/mkv), `audio_only`, `category`.

## Environment

Copy `.env.example` to `.env` and fill in Google OAuth credentials:
```
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
```

Scopes required: `https://www.googleapis.com/auth/youtube`
