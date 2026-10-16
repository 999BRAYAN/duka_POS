"""Starts duka_pos.

    python run.py

Opens on http://127.0.0.1:8080 by default (DUKA_HOST / DUKA_PORT to change).
Creates the database on first start, so `init_db.py` is optional.
"""

from duka import create_app
from duka.config import settings
from init_db import init_database

app = create_app()


def main() -> None:
    init_database()
    try:
        from waitress import serve
    except ImportError:  # the development server is fine for one shop's till
        app.run(host=settings.host, port=settings.port, threaded=True)
        return
    print(f"duka_pos is running at http://{settings.host}:{settings.port}")
    serve(app, host=settings.host, port=settings.port, threads=8)


if __name__ == "__main__":
    main()
