"""Starts duka_pos.

    python run.py

Opens on http://127.0.0.1:8080 by default (DUKA_HOST / DUKA_PORT to change).
Creates the database on first start, so `init_db.py` is optional.
"""

import os
import socket
import threading
import time
import webbrowser

from duka import create_app
from duka.config import settings
from init_db import init_database

app = create_app()


def _init_when_mysql_is_up(wait: float = 30.0) -> None:
    """MySQL can still be starting when start.bat launches us; retry for a while."""
    deadline = time.monotonic() + wait
    while True:
        try:
            init_database()
            return
        except Exception:  # noqa: BLE001 — wrong password and "not up yet" look the same
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.5)


def _address() -> str:
    """http://campusbites if setup-name.bat has been run, else the plain address."""
    try:
        with socket.create_connection(("campusbites", 80), timeout=0.5):
            return "http://campusbites"
    except OSError:
        return f"http://127.0.0.1:{settings.port}"


def _open_browser_when_ready() -> None:
    """Open the page as soon as the server accepts connections, not before."""
    for _ in range(100):
        try:
            with socket.create_connection(("127.0.0.1", settings.port), timeout=0.3):
                break
        except OSError:
            time.sleep(0.1)
    webbrowser.open(_address())


def main() -> None:
    _init_when_mysql_is_up()
    if os.environ.get("DUKA_OPEN_BROWSER") == "1":
        threading.Thread(target=_open_browser_when_ready, daemon=True).start()
    try:
        from waitress import serve
    except ImportError:  # the development server is fine for one shop's till
        app.run(host=settings.host, port=settings.port, threaded=True)
        return
    print(f"duka_pos is running at http://{settings.host}:{settings.port}")
    serve(app, host=settings.host, port=settings.port, threads=8)


if __name__ == "__main__":
    main()
