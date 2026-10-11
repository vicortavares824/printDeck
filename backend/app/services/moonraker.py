import httpx
from app.core.config import settings


class MoonrakerService:
    def __init__(self):
        self.base_url = settings.MOONRAKER_URL.rstrip("/")

    async def get_printer_status(self) -> dict:
        """
        Consulta telemetria da impressora: print_stats, toolhead, extruder, heater_bed
        """
        url = f"{self.base_url}/printer/objects/query"
        params = {
            "print_stats": "",
            "extruder": "",
            "heater_bed": "",
            "display_status": "",
        }
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json().get("result", {}).get("status", {})

            print_stats = data.get("print_stats", {})
            extruder = data.get("extruder", {})
            heater_bed = data.get("heater_bed", {})
            display_status = data.get("display_status", {})

            return {
                "state": print_stats.get("state", "disconnected"),
                "message": print_stats.get("message"),
                "filename": print_stats.get("filename"),
                "progress": display_status.get("progress", 0.0),
                "print_duration": print_stats.get("print_duration", 0.0),
                "filament_used": print_stats.get("filament_used", 0.0),
                "extruder_temp": extruder.get("temperature", 0.0),
                "extruder_target": extruder.get("target", 0.0),
                "bed_temp": heater_bed.get("temperature", 0.0),
                "bed_target": heater_bed.get("target", 0.0),
            }

    async def list_gcode_files(self) -> list[dict]:
        """
        Lista todos os arquivos gcode disponíveis no Moonraker
        """
        url = f"{self.base_url}/server/files/list"
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, params={"root": "gcodes"})
            response.raise_for_status()
            files_raw = response.json().get("result", [])

            files = []
            for item in files_raw:
                files.append({
                    "path": item.get("path"),
                    "size": item.get("size", 0),
                    "modified": item.get("modified"),
                    "estimated_time": item.get("estimated_time"),
                    "filament_total": item.get("filament_total"),
                })
            return files

    async def start_print(self, filename: str) -> dict:
        """
        Inicia a impressão de um arquivo
        """
        url = f"{self.base_url}/printer/print/start"
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(url, json={"filename": filename})
            response.raise_for_status()
            return response.json()


moonraker_service = MoonrakerService()
