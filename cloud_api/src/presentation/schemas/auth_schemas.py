from pydantic import BaseModel, EmailStr, Field
from src.domain.auth.entities import UserRole


# ── Requests ────────────────────────────────────────────────────
class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    email: EmailStr
    password: str = Field(..., min_length=8)
    role: UserRole = UserRole.VIEWER
    organization_id: int | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


# ── Responses ───────────────────────────────────────────────────
class TokenResponse(BaseModel):
    access_token: str
    token_type: str


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    role: UserRole
    organization_id: int | None
    is_active: bool

    model_config = {"from_attributes": True}
