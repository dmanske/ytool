# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**YTool** — Local web app with three modules:
1. **Downloader** — YouTube and Instagram videos/photos via `yt-dlp` with queue, cancel, trim, custom filename, drag-drop, persistent history
2. **Subscriptions** — Export, import, and transfer YouTube subscriptions between accounts via OAuth
3. **Playlists** — List, select, and transfer playlists (public + private) between YouTube accounts

See [DESIGN.md](DESIGN.md) for full architecture decisions and rationale.

## Stack

- **Python 3.12+** managed with `uv`
- **FastAPI** + uvicorn for the backend
- **yt-dlp** called via `asyncio.subprocess` (non-blocking, with cancel support)
- **Google OAuth** via `google-auth-oauthlib` + `google-api-python-client`
- **SSE (Server-Sent Events)** for real-time download/transfer progress
- **HTML/CSS/JS vanilla** + Tailwind via CDN + Lucide Icons (no build step)
- **YouTube IFrame API** for embedded video preview

## Commands

```bash
# Install dependencies
uv sync

# Run dev server (opens localhost:8000 automatically in browser)
uv run python app.py

# Run without opening browser
uv run python app.py --no-browser

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
  downloader.py     # Download, cancel, formats, thumbnail, history
  subscriptions.py  # OAuth, subscriptions, playlists
  config.py         # Config CRUD, open-folder (cross-platform)
services/       # All business logic
  ytdlp_service.py    # yt-dlp subprocess, progress parsing, cancel, trim
  youtube_auth.py     # OAuth flow + YouTube API (subs, playlists, videos)
  history_service.py  # Persistent download history (~/.ytool/history.json)
static/         # SPA with 4 tabs: Downloads, Subscriptions, Playlists, Config
  index.html         # Layout with sidebar, help modal, YouTube player
  app.js             # Queue, drag-drop, auto-inspect, theme toggle, player
  style.css          # Dark/light theme, sidebar, responsive components
config.py       # pydantic-settings: download dir, categories, OAuth creds
```

**Key patterns:**
- Downloads and transfers stream progress via SSE — always use `StreamingResponse` with `text/event-stream`
- yt-dlp is called as a subprocess, never imported directly, to avoid blocking the event loop
- Active downloads tracked in `_active_downloads` dict for cancellation support
- OAuth tokens stored in `~/.ytool/tokens/` (outside the repo)
- Download history stored in `~/.ytool/history.json` with thumbnails
- Download output path: `{base_dir}/{platform}/{category}/`
- Subscription/playlist transfers respect YouTube API rate limits (~1 req/s)
- OAuth uses `prompt="select_account consent"` so users can connect two different accounts without needing two browsers
- Open-folder is cross-platform: `open` (macOS), `explorer` (Windows), `xdg-open` (Linux)

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/download` | Start download (streams SSE progress) |
| POST | `/api/download/cancel` | Cancel a running download by ID |
| GET | `/api/formats` | Inspect available formats for a URL |
| GET | `/api/thumbnail` | Proxy thumbnail image (avoids CORS) |
| GET | `/api/history` | Get persistent download history |
| DELETE | `/api/history` | Clear download history |
| GET | `/api/subscriptions/export` | Export subscriptions as JSON or CSV |
| POST | `/api/subscriptions/import` | Import subscriptions from file (streams SSE) |
| POST | `/api/subscriptions/transfer` | Transfer subs between two accounts (streams SSE) |
| GET | `/api/subscriptions/playlists` | List playlists from source account |
| POST | `/api/subscriptions/playlists/transfer` | Transfer selected playlists (streams SSE) |
| GET | `/api/config` | Get current configuration |
| POST | `/api/config` | Update configuration |
| POST | `/api/config/open-folder` | Open folder in system file manager |

`DownloadRequest` fields: `url`, `quality`, `format`, `audio_only`, `category`, `filename`, `download_id`, `trim_start`, `trim_end`, `subtitles`, `sub_langs`, `thumbnail`.

## Environment

Copy `.env.example` to `.env` and fill in Google OAuth credentials:
```
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
BASE_DOWNLOAD_DIR=~/Downloads/YTool
```

Scopes required: `https://www.googleapis.com/auth/youtube`

Google OAuth is only needed for Subscriptions and Playlists modules. Downloads work without any configuration.
