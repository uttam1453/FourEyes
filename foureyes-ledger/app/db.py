import os

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URL = (
    f"postgresql+psycopg2://foureyes_ledger:{os.environ['PGPASS_FOUREYES_LEDGER']}"
    f"@{os.environ.get('POSTGRES_HOST', 'postgres')}:{os.environ.get('POSTGRES_PORT', '5432')}/foureyes_ledger"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
