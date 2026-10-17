from src.domain.organizations.entities import Organization
from src.domain.organizations.interfaces import IOrganizationRepository


class CreateOrganizationUseCase:
    def __init__(self, org_repo: IOrganizationRepository) -> None:
        self._repo = org_repo

    async def execute(self, name: str, slug: str) -> Organization:
        existing = await self._repo.get_by_slug(slug)
        if existing:
            raise ValueError(f"Slug {slug!r} já utilizado.")
        org = Organization(id=None, name=name, slug=slug)
        return await self._repo.create(org)


class ListOrganizationsUseCase:
    def __init__(self, org_repo: IOrganizationRepository) -> None:
        self._repo = org_repo

    async def execute(self) -> list[Organization]:
        return await self._repo.list_all()


class GetOrganizationUseCase:
    def __init__(self, org_repo: IOrganizationRepository) -> None:
        self._repo = org_repo

    async def execute(self, org_id: int) -> Organization:
        org = await self._repo.get_by_id(org_id)
        if not org:
            raise LookupError(f"Organização {org_id} não encontrada.")
        return org
