"""Tests run against a real MySQL/MariaDB — point them at a scratch database:

    DUKA_DB_PORT=3307 DUKA_DB_NAME=duka_v3_test python -m pytest tests

The database is created if missing and emptied before every test.
"""

import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ.setdefault("DUKA_DB_NAME", "duka_pos_test")
os.environ["DUKA_OLLAMA_URL"] = "http://127.0.0.1:1"      # tests never talk to a real model
os.environ["DUKA_OLLAMA_FIRST"] = "0"

from duka import create_app  # noqa: E402
from duka.db import Db, connect  # noqa: E402
from duka.repos.backup import TABLES, seed_walk_in_customer  # noqa: E402
from init_db import init_database  # noqa: E402
from api_helpers import Client  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _database():
    init_database()


@pytest.fixture(autouse=True)
def _clean():
    db = Db(connect())
    db.execute("SET FOREIGN_KEY_CHECKS = 0")
    for table in reversed(TABLES):
        db.execute(f"DELETE FROM `{table}`")
    db.execute("SET FOREIGN_KEY_CHECKS = 1")
    seed_walk_in_customer(db)
    db.close()


@pytest.fixture()
def app():
    return create_app()


@pytest.fixture()
def anon(app):
    return Client(app)


@pytest.fixture()
def manager(app):
    client = Client(app)
    r = client.post("/api/auth/setup", {"fullName": "Mary Manager", "username": "mary", "password": "secret1"})
    assert r.status_code == 200, r.get_json()
    return client


@pytest.fixture()
def cashier(app, manager):
    r = manager.post(
        "/api/users", {"fullName": "Carl Cashier", "username": "carl", "password": "cashpw1", "role": "cashier"}
    )
    assert r.status_code == 200, r.get_json()
    client = Client(app)
    assert client.post("/api/auth/login", {"username": "carl", "password": "cashpw1"}).status_code == 200
    return client
