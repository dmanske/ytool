import json

import aiofiles

from config import settings

HISTORY_PATH = settings.token_dir.parent / "history.json"


async def load_history() -> list[dict]:
    if not HISTORY_PATH.exists():
        return []
    async with aiofiles.open(HISTORY_PATH) as f:
        return json.loads(await f.read())


async def save_entry(entry: dict) -> None:
    history = await load_history()
    history.insert(0, entry)
    history = history[:100]  # keep last 100
    HISTORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    async with aiofiles.open(HISTORY_PATH, "w") as f:
        await f.write(json.dumps(history, ensure_ascii=False, indent=2))


async def clear_history() -> None:
    if HISTORY_PATH.exists():
        HISTORY_PATH.unlink()
