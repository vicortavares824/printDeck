from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Se você adicionar um PostgreSQL no Render, a DATABASE_URL virá como postgres://...
    # Ajustamos automaticamente para postgresql+asyncpg se necessário
    DATABASE_URL: str = "sqlite+aiosqlite:///./cloud_database.db"
    API_SECRET_KEY: str = "printdeck-secret-token"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    @property
    def async_database_url(self) -> str:
        url = self.DATABASE_URL
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+asyncpg://", 1)
        elif url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
        return url


settings = Settings()
