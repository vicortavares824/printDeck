from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.organizations.entities import Organization
from src.domain.organizations.interfaces import IOrganizationRepository
from src.infrastructure.database.models.organization_models import OrganizationModel


class SQLOrganizationRepository(IOrganizationRepository):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def _to_entity(self, model: OrganizationModel) -> Organization:
        return Organization(
            id=model.id,
            name=model.name,
            slug=model.slug,
            is_active=model.is_active,
            created_at=model.created_at,
        )

    async def get_by_id(self, org_id: int) -> Organization | None:
        result = await self._session.execute(select(OrganizationModel).where(OrganizationModel.id == org_id))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def get_by_slug(self, slug: str) -> Organization | None:
        result = await self._session.execute(select(OrganizationModel).where(OrganizationModel.slug == slug))
        model = result.scalars().first()
        return self._to_entity(model) if model else None

    async def list_all(self) -> list[Organization]:
        result = await self._session.execute(select(OrganizationModel).order_by(OrganizationModel.name))
        return [self._to_entity(m) for m in result.scalars().all()]

    async def create(self, org: Organization) -> Organization:
        model = OrganizationModel(name=org.name, slug=org.slug, is_active=org.is_active)
        self._session.add(model)
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)

    async def update(self, org: Organization) -> Organization:
        result = await self._session.execute(select(OrganizationModel).where(OrganizationModel.id == org.id))
        model = result.scalars().first()
        if not model:
            raise LookupError(f"Organization {org.id} not found.")
        model.name = org.name
        model.slug = org.slug
        model.is_active = org.is_active
        await self._session.commit()
        await self._session.refresh(model)
        return self._to_entity(model)
