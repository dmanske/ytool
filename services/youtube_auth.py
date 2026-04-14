import asyncio
import json

import aiofiles
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build

from config import settings

SCOPES = ["https://www.googleapis.com/auth/youtube"]


def _client_config() -> dict:
    return {
        "web": {
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "redirect_uris": [settings.oauth_redirect_uri],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    }


def create_flow() -> Flow:
    return Flow.from_client_config(
        _client_config(),
        scopes=SCOPES,
        redirect_uri=settings.oauth_redirect_uri,
    )


async def get_credentials(account_key: str) -> Credentials | None:
    token_path = settings.token_dir / f"{account_key}.json"
    if not token_path.exists():
        return None

    async with aiofiles.open(token_path) as f:
        data = json.loads(await f.read())

    creds = Credentials.from_authorized_user_info(data, SCOPES)

    if creds.expired and creds.refresh_token:
        await asyncio.to_thread(creds.refresh, Request())
        await save_credentials(account_key, creds)

    return creds if creds.valid else None


async def save_credentials(account_key: str, creds: Credentials) -> None:
    token_path = settings.token_dir / f"{account_key}.json"
    async with aiofiles.open(token_path, "w") as f:
        await f.write(creds.to_json())


async def delete_credentials(account_key: str) -> None:
    token_path = settings.token_dir / f"{account_key}.json"
    if token_path.exists():
        token_path.unlink()


def list_subscriptions(creds: Credentials) -> list[dict]:
    """Synchronous — wrap with asyncio.to_thread in async contexts."""
    youtube = build("youtube", "v3", credentials=creds)
    results, page_token = [], None
    while True:
        resp = (
            youtube.subscriptions()
            .list(part="snippet", mine=True, maxResults=50, pageToken=page_token)
            .execute()
        )
        for item in resp.get("items", []):
            results.append(
                {
                    "channel_id": item["snippet"]["resourceId"]["channelId"],
                    "title": item["snippet"]["title"],
                    "thumbnail": (
                        item["snippet"].get("thumbnails", {})
                        .get("default", {})
                        .get("url", "")
                    ),
                }
            )
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return results


def subscribe_to_channel(youtube, channel_id: str) -> None:
    """Synchronous — wrap with asyncio.to_thread in async contexts."""
    youtube.subscriptions().insert(
        part="snippet",
        body={
            "snippet": {
                "resourceId": {
                    "kind": "youtube#channel",
                    "channelId": channel_id,
                }
            }
        },
    ).execute()


def list_playlists(creds: Credentials) -> list[dict]:
    """List all playlists (public + private) for the authenticated account.
    Synchronous — wrap with asyncio.to_thread in async contexts."""
    youtube = build("youtube", "v3", credentials=creds)
    results, page_token = [], None
    while True:
        resp = (
            youtube.playlists()
            .list(part="snippet,contentDetails,status", mine=True, maxResults=50, pageToken=page_token)
            .execute()
        )
        for item in resp.get("items", []):
            snippet = item["snippet"]
            results.append(
                {
                    "playlist_id": item["id"],
                    "title": snippet["title"],
                    "description": snippet.get("description", ""),
                    "privacy": item.get("status", {}).get("privacyStatus", "public"),
                    "video_count": item.get("contentDetails", {}).get("itemCount", 0),
                    "thumbnail": (
                        snippet.get("thumbnails", {})
                        .get("medium", snippet.get("thumbnails", {}).get("default", {}))
                        .get("url", "")
                    ),
                }
            )
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return results


def list_playlist_items(youtube, playlist_id: str) -> list[dict]:
    """List all video IDs in a playlist.
    Synchronous — wrap with asyncio.to_thread in async contexts."""
    results, page_token = [], None
    while True:
        resp = (
            youtube.playlistItems()
            .list(part="snippet,contentDetails", playlistId=playlist_id, maxResults=50, pageToken=page_token)
            .execute()
        )
        for item in resp.get("items", []):
            video_id = item["contentDetails"]["videoId"]
            title = item["snippet"].get("title", video_id)
            results.append({"video_id": video_id, "title": title})
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return results


def create_playlist(youtube, title: str, description: str, privacy: str) -> str:
    """Create a playlist and return its ID.
    Synchronous — wrap with asyncio.to_thread in async contexts."""
    # Clamp privacy to valid values; default private for safety
    valid = {"public", "private", "unlisted"}
    privacy_status = privacy if privacy in valid else "private"
    resp = youtube.playlists().insert(
        part="snippet,status",
        body={
            "snippet": {"title": title, "description": description},
            "status": {"privacyStatus": privacy_status},
        },
    ).execute()
    return resp["id"]


def add_video_to_playlist(youtube, playlist_id: str, video_id: str) -> None:
    """Add a video to a playlist.
    Synchronous — wrap with asyncio.to_thread in async contexts."""
    youtube.playlistItems().insert(
        part="snippet",
        body={
            "snippet": {
                "playlistId": playlist_id,
                "resourceId": {"kind": "youtube#video", "videoId": video_id},
            }
        },
    ).execute()
