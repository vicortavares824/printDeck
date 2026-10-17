from abc import ABC, abstractmethod
from .entities import Organization


class IOrganizationRepository(ABC):
    @abstractmethod
    async def get_by_id(self, org_id: int) -> Organization | None: ...

    @abstractmethod
    async def get_by_slug(self, slug: str) -> Organization | None: ...

    @abstractmethod
    async def list_all(self) -> list[Organization]: ...

    @abstractmethod
    async def create(self, org: Organization) -> Organization: ...

    @abstractmethod
    async def update(self, org: Organization) -> Organization: ...
