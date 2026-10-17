from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession

from src.application.auth.use_cases import LoginUserUseCase, RegisterUserUseCase
from src.infrastructure.config import settings
from src.infrastructure.database.connection import get_db
from src.infrastructure.database.repositories.user_repository import SQLUserRepository
from src.infrastructure.security import get_current_user
from src.domain.auth.entities import User
from src.presentation.schemas.auth_schemas import RegisterRequest, TokenResponse, UserResponse

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    body: RegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    """Cria um novo usuário na plataforma."""
    repo = SQLUserRepository(db)
    use_case = RegisterUserUseCase(repo)
    try:
        user = await use_case.execute(
            name=body.name,
            email=body.email,
            password=body.password,
            role=body.role,
            org_id=body.organization_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(e))
    return UserResponse(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        organization_id=user.organization_id,
        is_active=user.is_active,
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Autentica um usuário e retorna o JWT Bearer Token."""
    repo = SQLUserRepository(db)
    use_case = LoginUserUseCase(repo, settings.JWT_SECRET_KEY, settings.JWT_EXPIRE_MINUTES)
    try:
        result = await use_case.execute(form.username, form.password)
    except PermissionError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )
    return TokenResponse(**result)


@router.get("/me", response_model=UserResponse)
async def me(current_user: User = Depends(get_current_user)) -> UserResponse:
    """Retorna os dados do usuário autenticado."""
    return UserResponse(
        id=current_user.id,
        name=current_user.name,
        email=current_user.email,
        role=current_user.role,
        organization_id=current_user.organization_id,
        is_active=current_user.is_active,
    )
