import asyncio
from sqlalchemy import select

from app.core.database import AsyncSessionLocal, Base, engine
from app.models.app_sync import AppSync
from app.models.printer import PrintJob, SpoolRecord
from app.models.supply_item import SupplyItem


async def init_db() -> None:
    """Cria as tabelas do banco de dados e popula dados iniciais (seed)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as session:
        # Seed de carretéis apenas se a tabela estiver vazia
        result = await session.execute(select(SpoolRecord).limit(1))
        if result.scalars().first() is None:
            session.add_all(
                [
                    SpoolRecord(
                        spoolman_id=1,
                        name="PLA Preto",
                        material="PLA",
                        color_hex="#1A1A1A",
                        vendor="3D Prima",
                        initial_weight_grams=1000.0,
                        remaining_weight_grams=850.0,
                    ),
                    SpoolRecord(
                        spoolman_id=2,
                        name="PETG Azul",
                        material="PETG",
                        color_hex="#0066CC",
                        vendor="eSun",
                        initial_weight_grams=1000.0,
                        remaining_weight_grams=1000.0,
                    ),
                ]
            )

        # Seed de itens de suprimento (SupplyHub) apenas se vazio
        result = await session.execute(select(SupplyItem).limit(1))
        if result.scalars().first() is None:
            session.add_all(
                [
                    SupplyItem(
                        name="Filamento PLA Preto 1kg",
                        description="Filamento PLA para impressão 3D",
                        category="Filamentos",
                        sku="FIL-PLA-001",
                        quantity=10,
                        min_stock=2,
                        unit="carretel",
                        location="Prateleira A",
                    ),
                    SupplyItem(
                        name="Cola Bastão",
                        description="Adesivo em bastão para mesa de impressão",
                        category="Acessórios",
                        sku="ACC-COLA-001",
                        quantity=20,
                        min_stock=5,
                        unit="unidade",
                        location="Prateleira B",
                    ),
                ]
            )

        await session.commit()


if __name__ == "__main__":
    asyncio.run(init_db())
    print("Banco de dados inicializado com sucesso.")
