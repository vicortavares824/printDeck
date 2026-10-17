from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.categories.use_cases import CreateCategoryUseCase, DeleteCategoryUseCase, ListCategoriesUseCase
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.category_repository import SQLCategoryRepository
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.category_schemas import CategoryResponse, CreateCategoryRequest

router = APIRouter(prefix="/categories", tags=["Categories"])


@router.get("/org/{org_id}", response_model=list[CategoryResponse])
async def list_categories(org_id: int, db: AsyncSession = Depends(get_db)) -> list[CategoryResponse]:
    """Lista categorias de uma organização."""
    repo = SQLCategoryRepository(db)
    cats = await ListCategoriesUseCase(repo).execute(org_id)
    return [CategoryResponse(id=c.id, name=c.name, description=c.description, organization_id=c.organization_id, created_at=c.created_at) for c in cats]


@router.post("/org/{org_id}", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_category(
    org_id: int,
    body: CreateCategoryRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> CategoryResponse:
    """Cria uma categoria em uma organização. Requer autenticação."""
    repo = SQLCategoryRepository(db)
    cat = await CreateCategoryUseCase(repo).execute(body.name, body.description, org_id)
    return CategoryResponse(id=cat.id, name=cat.name, description=cat.description, organization_id=cat.organization_id, created_at=cat.created_at)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(
    category_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> None:
    """Remove uma categoria. Requer autenticação."""
    repo = SQLCategoryRepository(db)
    try:
        await DeleteCategoryUseCase(repo).execute(category_id)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
