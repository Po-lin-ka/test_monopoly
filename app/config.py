from __future__ import annotations
import os
from dataclasses import dataclass
from dotenv import load_dotenv
load_dotenv()
@dataclass(frozen=True)
class Settings:
    user: str=os.getenv('ORACLE_USER','monopoly')
    password: str=os.getenv('ORACLE_PASSWORD','123321')
    dsn: str=os.getenv('ORACLE_DSN','localhost:1521/FREEPDB1')
    poll_interval_ms: int=int(os.getenv('POLL_INTERVAL_MS','2000'))
    connect_timeout_seconds: float=float(os.getenv('CONNECT_TIMEOUT_SECONDS','5'))
    call_timeout_ms: int=int(os.getenv('CALL_TIMEOUT_MS','5000'))
settings=Settings()
