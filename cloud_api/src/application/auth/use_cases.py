from datetime import datetime, timedelta
from typing import Any

from jose import jwt
from passlib.context import CryptContext

from src.domain.auth.entities import User, UserRole
from src.domain.auth.interfaces import IUserRepository

PWD_CONTEXT = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    return PWD_CONTEXT.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return PWD_CONTEXT.verify(plain, hashed)


def create_access_token(data: dict[str, Any], secret_key: str, expire_minutes: int) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=expire_minutes)
    to_encode["exp"] = expire
    return jwt.encode(to_encode, secret_key, algorithm="HS256")


class RegisterUserUseCase:
    def __init__(self, user_repo: IUserRepository) -> None:
        self._repo = user_repo

    async def execute(self, name: str, email: str, password: str, role: UserRole, org_id: int | None) -> User:
        existing = await self._repo.get_by_email(email)
        if existing:
            raise ValueError(f"E-mail {email!r} já cadastrado.")
        user = User(
            id=None,
            name=name,
            email=email,
            hashed_password=hash_password(password),
            role=role,
            organization_id=org_id,
        )
        return await self._repo.create(user)


class LoginUserUseCase:
    def __init__(self, user_repo: IUserRepository, secret_key: str, token_expire_minutes: int) -> None:
        self._repo = user_repo
        self._secret = secret_key
        self._expire = token_expire_minutes

    async def execute(self, email: str, password: str) -> dict[str, str]:
        user = await self._repo.get_by_email(email)
        if not user or not verify_password(password, user.hashed_password):
            raise PermissionError("Credenciais inválidas.")
        if not user.is_active:
            raise PermissionError("Conta desativada.")
        token = create_access_token(
            {"sub": str(user.id), "role": user.role, "org": user.organization_id},
            self._secret,
            self._expire,
        )
        return {"access_token": token, "token_type": "bearer"}
