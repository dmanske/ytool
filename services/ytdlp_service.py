import asyncio
import json
import re
from pathlib import Path
from typing import AsyncGenerator

from config import settings


def _friendly_vcodec(codec: str) -> str:
    c = codec.lower()
    if c.startswith("avc") or c.startswith("h264"):  return "H.264"
    if c.startswith("hvc") or c.startswith("h265"):  return "H.265"
    if c.startswith("av0") or c.startswith("av1"):   return "AV1"
    if c.startswith("vp9"):                           return "VP9"
    if c.startswith("vp8"):                           return "VP8"
    return codec.split(".")[0].upper()


def _friendly_acodec(codec: str) -> str:
    c = codec.lower()
    if c.startswith("mp4a"):  return "AAC"
    if c.startswith("opus"):  return "Opus"
    if c.startswith("mp3"):   return "MP3"
    if c.startswith("vorbis"): return "Vorbis"
    return codec.split(".")[0].upper()


def _res_label(height: int) -> str:
    return {2160: "4K", 1440: "2K", 1080: "1080p", 720: "720p",
            480: "480p", 360: "360p", 240: "240p", 144: "144p"}.get(height, f"{height}p")


async def get_formats(url: str) -> list[dict]:
    """Return available formats for a URL using yt-dlp -J (JSON dump)."""
    proc = await asyncio.create_subprocess_exec(
        "yt-dlp", "--no-playlist", "-J", url,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await proc.communicate()
    if proc.returncode != 0:
        return []

    info = json.loads(stdout)
    formats = []
    for f in info.get("formats", []):
        vcodec = f.get("vcodec", "none")
        acodec = f.get("acodec", "none")
        height = f.get("height")
        fps = f.get("fps")
        tbr = f.get("tbr")
        filesize = f.get("filesize") or f.get("filesize_approx")
        ext = f.get("ext", "")
        format_id = f.get("format_id", "")

        size_str = f"  ~{filesize // 1_048_576}MB" if filesize else ""

        if vcodec == "none" and acodec != "none":
            codec = _friendly_acodec(acodec)
            bitrate = f"{int(tbr or 0)}kbps" if tbr else ""
            label = f"{codec} {bitrate} .{ext}{size_str}".strip()
            kind = "audio"
        elif vcodec != "none":
            res = _res_label(height) if height else ext.upper()
            fps_str = f" {int(fps)}fps" if fps and fps > 30 else ""
            codec = _friendly_vcodec(vcodec)
            label = f"{res}{fps_str}  {codec} .{ext}{size_str}"
            kind = "video+audio" if acodec != "none" else "video"
        else:
            continue

        formats.append({"id": format_id, "label": label, "kind": kind, "height": height or 0})

    # sort: height desc (best quality first); audio at bottom; video+audio preferred over video-only at same height
    kind_tiebreak = {"video+audio": 0, "video": 1, "audio": 2}
    formats.sort(key=lambda f: (0 if f["kind"] != "audio" else 1, -f["height"], kind_tiebreak.get(f["kind"], 9)))

    return {
        "title": info.get("title", ""),
        "thumbnail": info.get("thumbnail", ""),
        "duration": info.get("duration"),
        "uploader": info.get("uploader", ""),
        "artist": info.get("artist") or info.get("creator") or "",
        "track": info.get("track") or "",
        "formats": formats,
    }


_PROGRESS_RE = re.compile(
    r"\[download\]\s+(?P<percent>[\d.]+)%\s+of\s+"
    r"(?P<total>\S+)\s+at\s+(?P<speed>\S+)\s+ETA\s+(?P<eta>\S+)"
)


def detect_platform(url: str) -> str:
    if "youtube.com" in url or "youtu.be" in url:
        return "youtube"
    if "instagram.com" in url:
        return "instagram"
    return "other"


def _safe_filename(name: str) -> str:
    """Strip characters that are invalid in filenames across platforms."""
    return re.sub(r'[\\/:*?"<>|]', "", name).strip()


def build_ytdlp_args(
    url: str,
    quality: str,
    fmt: str,
    audio_only: bool,
    output_dir: Path,
    format_id: str | None = None,
    subtitles: bool = False,
    sub_langs: str = "en,pt",
    format_kind: str | None = None,
    filename: str = "",
) -> list[str]:
    name = _safe_filename(filename) if filename else "%(title)s"
    output_template = str(output_dir / f"{name}.%(ext)s")
    # --no-playlist: for YouTube, prevent downloading entire playlist when URL has &list=
    # Not applied to Instagram so carousel posts (multiple photos/videos) download fully
    no_playlist = ["--no-playlist"] if "youtube" in url or "youtu.be" in url else []
    args = ["yt-dlp", "--newline", *no_playlist, "-o", output_template]

    if audio_only:
        args += ["-x", "--audio-format", "mp3"]
    elif format_id:
        # always attempt +bestaudio merge unless explicitly known to already have audio
        has_audio = format_kind in ("video+audio", "audio")
        f_selector = format_id if has_audio else f"{format_id}+bestaudio"
        args += ["-f", f_selector, "--merge-output-format", fmt]
    elif quality != "best":
        height = quality.replace("p", "")
        args += [
            "-f", f"bestvideo[height<={height}]+bestaudio/best[height<={height}]",
            "--merge-output-format", fmt,
        ]
    else:
        args += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", fmt]

    if subtitles:
        # exclude live_chat which yt-dlp treats as a subtitle track
        langs = sub_langs or "en,pt"
        args += [
            "--write-subs", "--write-auto-subs",
            "--sub-langs", langs,
            "--convert-subs", "srt",
            "--ignore-errors",   # subtitle failures must not abort the video download
        ]

    args.append(url)
    return args


def parse_progress_line(line: str) -> dict:
    m = _PROGRESS_RE.search(line)
    if m:
        return {"status": "progress", **m.groupdict()}
    return {"status": "log", "message": line}


async def download_with_progress(
    url: str,
    quality: str,
    fmt: str,
    audio_only: bool,
    category: str,
    format_id: str | None = None,
    format_kind: str | None = None,
    subtitles: bool = False,
    sub_langs: str = "en,pt",
    filename: str = "",
) -> AsyncGenerator[str, None]:
    platform = detect_platform(url)
    output_dir = settings.base_download_dir / platform / category
    output_dir.mkdir(parents=True, exist_ok=True)

    args = build_ytdlp_args(url, quality, fmt, audio_only, output_dir, format_id, subtitles, sub_langs, format_kind, filename)

    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )

    async for raw_line in proc.stdout:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line:
            continue
        data = parse_progress_line(line)
        yield f"data: {json.dumps(data)}\n\n"

    await proc.wait()

    if proc.returncode != 0:
        yield f"data: {json.dumps({'status': 'error', 'message': f'yt-dlp exited with code {proc.returncode}'})}\n\n"
    else:
        yield f"data: {json.dumps({'status': 'done', 'output_dir': str(output_dir)})}\n\n"
