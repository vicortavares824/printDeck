from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.categories.entities import Category
from src.domain.categories.interfaces import ICategoryRepository
from src.infrastructure.database.models.category_models import CategoryModel


class SQLCategoryRepository(ICategoryRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: CategoryModel) -> Category:
        return Category(
            id=model.id,
            name=model.name,
            description=model.description,
            organization_id=model.organization_id,
            created_at=model.created_at,
        )

    async def get_by_id(self, category_id: int) -> Category | None:
        result = await self._session.execute(select(CategoryModel).where(CategoryModel.id == category_id))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def list_by_organization(self, org_id: int) -> list[Category]:
        result = await self._session.execute(
            select(CategoryModel).where(CategoryModel.organization_id == org_id).order_by(CategoryModel.name)
        )
        return [self._to_entity(m) for m in result.scalars().all()]

    async def create(self, category: Category) -> Category:
        model = CategoryModel(name=category.name, description=category.description, organization_id=category.organization_id)
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def update(self, category: Category) -> Category:
        result = await self._session.execute(select(CategoryModel).where(CategoryModel.id == category.id))
        model = result.scalars().first()
        if not model:
            raise LookupError()
        model.name = category.name
        model.description = category.description
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def delete(self, category_id: int) -> None:
        result = await self._session.execute(select(CategoryModel).where(CategoryModel.id == category_id))
        model = result.scalars().first()
        if model:
            await self._session.delete(model)
            await self._session.commit()
