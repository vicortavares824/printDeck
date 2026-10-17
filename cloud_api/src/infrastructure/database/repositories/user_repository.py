from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.auth.entities import User, UserRole
from src.domain.auth.interfaces import IUserRepository
from src.infrastructure.database.models.auth_models import UserModel


class SQLUserRepository(IUserRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: UserModel) -> User:
        return User(
            id=model.id,
            name=model.name,
            email=model.email,
            hashed_password=model.hashed_password,
            role=UserRole(model.role),
            organization_id=model.organization_id,
            is_active=model.is_active,
            created_at=model.created_at,
        )

    async def get_by_email(self, email: str) -> User | None:
        result = await self._session.execute(select(UserModel).where(UserModel.email == email))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def get_by_id(self, user_id: int) -> User | None:
        result = await self._session.execute(select(UserModel).where(UserModel.id == user_id))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def create(self, user: User) -> User:
        model = UserModel(
            name=user.name,
            email=user.email,
            hashed_password=user.hashed_password,
            role=user.role.value,
            organization_id=user.organization_id,
            is_active=user.is_active,
        )
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)
