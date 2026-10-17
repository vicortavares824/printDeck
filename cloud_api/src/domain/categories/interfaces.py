from abc import ABC, abstractmethod
from .entities import Category


class ICategoryRepository(ABC):
    @abstractmethod
    async def get_by_id(self, category_id: int) -> Category | None: ...

    @abstractmethod
    async def list_by_organization(self, org_id: int) -> list[Category]: ...

    @abstractmethod
    async def create(self, category: Category) -> Category: ...

    @abstractmethod
    async def update(self, category: Category) -> Category: ...

    @abstractmethod
    async def delete(self, category_id: int) -> None: ...
