from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Organization:
    id: int | None
    name: str
    slug: str
    is_active: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
