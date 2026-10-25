from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Se você adicionar um PostgreSQL no Render, a DATABASE_URL virá como postgres://...
    # Ajustamos automaticamente para postgresql+asyncpg se necessário
    DATABASE_URL: str = "sqlite+aiosqlite:///./cloud_database.db"
    API_SECRET_KEY: str = "printdeck-secret-token"

    # Código secreto de administrador do SupplyHub. Um dispositivo que apresenta
    # este código (header x-admin-code) pode editar/excluir QUALQUER item do
    # inventário compartilhado, independente de quem o criou. Configure via
    # variável de ambiente ADMIN_CODE no ambiente de produção (Render/.env).
    # Vazio ou "disabled" => nenhum admin é concedido (acesso admin desligado).
    ADMIN_CODE: str = "disabled"

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
