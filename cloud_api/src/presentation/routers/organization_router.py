from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.organizations.use_cases import (
    CreateOrganizationUseCase,
    GetOrganizationUseCase,
    ListOrganizationsUseCase,
)
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.organization_repository import SQLOrganizationRepository
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.organization_schemas import CreateOrganizationRequest, OrganizationResponse

router = APIRouter(prefix="/organizations", tags=["Organizations"])


@router.get("/", response_model=list[OrganizationResponse])
async def list_organizations(db: AsyncSession = Depends(get_db)) -> list[OrganizationResponse]:
    """Lista todas as organizações."""
    repo = SQLOrganizationRepository(db)
    orgs = await ListOrganizationsUseCase(repo).execute()
    return [OrganizationResponse(id=o.id, name=o.name, slug=o.slug, is_active=o.is_active, created_at=o.created_at) for o in orgs]


@router.get("/{org_id}", response_model=OrganizationResponse)
async def get_organization(org_id: int, db: AsyncSession = Depends(get_db)) -> OrganizationResponse:
    """Retorna uma organização pelo ID."""
    repo = SQLOrganizationRepository(db)
    try:
        org = await GetOrganizationUseCase(repo).execute(org_id)
    except LookupError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    return OrganizationResponse(id=org.id, name=org.name, slug=org.slug, is_active=org.is_active, created_at=org.created_at)


@router.post("/", response_model=OrganizationResponse, status_code=status.HTTP_201_CREATED)
async def create_organization(
    body: CreateOrganizationRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
) -> OrganizationResponse:
    """Cria uma nova organização. Requer autenticação."""
    repo = SQLOrganizationRepository(db)
    try:
        org = await CreateOrganizationUseCase(repo).execute(body.name, body.slug)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))
    return OrganizationResponse(id=org.id, name=org.name, slug=org.slug, is_active=org.is_active, created_at=org.created_at)
