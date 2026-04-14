from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    base_download_dir: Path = Path.home() / "Downloads" / "YTool"
    token_dir: Path = Path.home() / ".ytool" / "tokens"
    categories: list[str] = ["Música", "Tutoriais", "Filmes", "Outros"]
    google_client_id: str | None = None
    google_client_secret: str | None = None
    oauth_redirect_uri: str = "http://localhost:8000/api/subscriptions/oauth/callback"
    host: str = "127.0.0.1"
    port: int = 8000


settings = Settings()
settings.base_download_dir.mkdir(parents=True, exist_ok=True)
settings.token_dir.mkdir(parents=True, exist_ok=True)
