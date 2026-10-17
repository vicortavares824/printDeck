from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Category:
    id: int | None
    name: str
    description: str | None
    organization_id: int
    created_at: datetime = field(default_factory=datetime.utcnow)
