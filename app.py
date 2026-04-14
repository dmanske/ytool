import sys
import asyncio
import webbrowser
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from config import settings
from routers import downloader, subscriptions, config


@asynccontextmanager
async def lifespan(app: FastAPI):
    if "--no-browser" not in sys.argv:
        asyncio.get_event_loop().call_later(
            1.0, webbrowser.open, f"http://{settings.host}:{settings.port}"
        )
    yield


app = FastAPI(title="YTool", lifespan=lifespan)

app.include_router(downloader.router, prefix="/api")
app.include_router(subscriptions.router, prefix="/api/subscriptions")
app.include_router(config.router, prefix="/api/config")

app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
async def serve_index():
    return FileResponse("static/index.html")


def main():
    import uvicorn

    uvicorn.run("app:app", host=settings.host, port=settings.port, reload=False)


if __name__ == "__main__":
    main()
