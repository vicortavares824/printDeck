.PHONY: run dev install migrate revision

install:
	pip install -r requirements.txt

run:
	uvicorn src.main:app --host 0.0.0.0 --port 8000

dev:
	uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

migrate:
	alembic upgrade head

revision:
	alembic revision --autogenerate -m "$(MSG)"
