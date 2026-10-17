from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class UserRole(str, Enum):
    ADMIN = "admin"
    MANAGER = "manager"
    VIEWER = "viewer"


@dataclass
class User:
    id: int | None
    name: str
    email: str
    hashed_password: str
    role: UserRole
    organization_id: int | None
    is_active: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
