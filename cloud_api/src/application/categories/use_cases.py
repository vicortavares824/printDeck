from src.domain.categories.entities import Category
from src.domain.categories.interfaces import ICategoryRepository


class CreateCategoryUseCase:
    def __init__(self, repo: ICategoryRepository) -> None:
        self._repo = repo

    async def execute(self, name: str, description: str | None, org_id: int) -> Category:
        cat = Category(id=None, name=name, description=description, organization_id=org_id)
        return await self._repo.create(cat)


class ListCategoriesUseCase:
    def __init__(self, repo: ICategoryRepository) -> None:
        self._repo = repo

    async def execute(self, org_id: int) -> list[Category]:
        return await self._repo.list_by_organization(org_id)


class DeleteCategoryUseCase:
    def __init__(self, repo: ICategoryRepository) -> None:
        self._repo = repo

    async def execute(self, category_id: int) -> None:
        cat = await self._repo.get_by_id(category_id)
        if not cat:
            raise LookupError(f"Categoria {category_id} não encontrada.")
        await self._repo.delete(category_id)
