from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    MOONRAKER_URL: str = "http://127.0.0.1:7125"
    SPOOLMAN_URL: str = "http://127.0.0.1:7912"
    DATABASE_URL: str = "sqlite+aiosqlite:///./database.db"
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    CLOUD_API_URL: str | None = None
    CLOUD_API_KEY: str | None = "printdeck-secret-token"
    PRINTER_ID: str = "printer_01"

    SUPPLY_HUB_PUBLIC_READ: bool = True

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()
