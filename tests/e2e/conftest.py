"""Browser tests: a real server on a free port, driven in your installed Chrome.

    DUKA_DB_PORT=3307 DUKA_DB_NAME=duka_v3_e2e python -m pytest tests/e2e

Set DUKA_SHOTS=/some/folder to keep a screenshot of key steps.
"""

import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

playwright_sync = pytest.importorskip("playwright.sync_api")

ROOT = Path(__file__).resolve().parents[2]
from ui_helpers import Ui, first_run  # noqa: E402


@pytest.fixture(scope="session")
def server():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    env = {**os.environ, "DUKA_PORT": str(port), "DUKA_HOST": "127.0.0.1"}
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "run.py")], cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    base = f"http://127.0.0.1:{port}"
    for _ in range(80):
        try:
            urllib.request.urlopen(base + "/api/session", timeout=1)
            break
        except Exception:
            time.sleep(0.25)
    else:
        proc.kill()
        raise RuntimeError("the test server did not start")
    yield base
    proc.kill()


@pytest.fixture(scope="session")
def browser():
    with playwright_sync.sync_playwright() as p:
        try:
            b = p.chromium.launch(channel="chrome", headless=True)
        except Exception:
            b = p.chromium.launch(headless=True)
        yield b
        b.close()


@pytest.fixture()
def ui(browser, server):
    u = Ui(browser, server)
    yield u
    problems = list(u.problems)
    u.close()
    assert not problems, "browser reported problems:\n" + "\n".join(problems)


@pytest.fixture()
def manager_ui(ui):
    """Set up the shop through the first-run screen, then land on Products."""
    first_run(ui)
    return ui
