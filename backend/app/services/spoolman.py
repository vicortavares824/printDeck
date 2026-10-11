import httpx
from app.core.config import settings


class SpoolmanService:
    def __init__(self):
        self.base_url = settings.SPOOLMAN_URL.rstrip("/")

    async def list_spools(self) -> list[dict]:
        """
        Lista bobinas cadastradas no Spoolman
        """
        url = f"{self.base_url}/api/v1/spool"
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            spools_raw = response.json()

            results = []
            for s in spools_raw:
                filament = s.get("filament") or {}
                vendor = filament.get("vendor") or {}
                results.append({
                    "id": s.get("id"),
                    "filament_name": filament.get("name"),
                    "material": filament.get("material"),
                    "vendor_name": vendor.get("name"),
                    "remaining_weight": s.get("remaining_weight"),
                    "initial_weight": s.get("initial_weight"),
                    "color_hex": filament.get("color_hex"),
                })
            return results

    async def get_spool(self, spool_id: int) -> dict:
        """
        Obtém detalhes de um carretel específico
        """
        url = f"{self.base_url}/api/v1/spool/{spool_id}"
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.json()


spoolman_service = SpoolmanService()
