"""duka_pos — Version 3: Python + MySQL back end, HTML/CSS/JavaScript front end."""

from datetime import date, datetime
from decimal import Decimal

from flask import Flask, g, jsonify, request, send_from_directory
from flask.json.provider import DefaultJSONProvider
from werkzeug.exceptions import HTTPException

from .config import WEB_DIR, settings

VERSION = "3.0.0"


class _Json(DefaultJSONProvider):
    @staticmethod
    def default(o):
        if isinstance(o, datetime):
            return o.isoformat(timespec="milliseconds")
        if isinstance(o, date):
            return o.isoformat()
        if isinstance(o, Decimal):
            return float(o)
        return DefaultJSONProvider.default(o)


def create_app() -> Flask:
    app = Flask(__name__, static_folder=None)
    app.json = _Json(app)
    app.json.sort_keys = False
    app.config.update(
        SECRET_KEY=settings.secret_key,
        SESSION_COOKIE_NAME="duka_session",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        MAX_CONTENT_LENGTH=64 * 1024 * 1024,
    )

    from .api import bp as api_bp

    app.register_blueprint(api_bp)

    @app.before_request
    def _require_ajax_header():
        # Browsers won't add a custom header to a cross-site request, so
        # demanding one on every write is a cheap CSRF defence on top of the
        # SameSite cookie.
        if request.path.startswith("/api/") and request.method not in ("GET", "HEAD", "OPTIONS"):
            if request.headers.get("X-Requested-With") != "duka":
                return jsonify({"error": {"code": "forbidden", "message": "Request refused."}}), 403

    @app.teardown_appcontext
    def _close_db(_exc):
        conn = g.pop("db", None)
        if conn is not None:
            conn.close()

    @app.errorhandler(HTTPException)
    def _http_error(error: HTTPException):
        if request.path.startswith("/api/"):
            return jsonify({"error": {"code": "http_error", "message": error.description}}), error.code
        return error

    @app.errorhandler(ValueError)
    @app.errorhandler(TypeError)
    def _bad_value(error):
        if request.path.startswith("/api/"):
            return jsonify({"error": {"code": "invalid", "message": "Some of the values sent weren't valid."}}), 400
        raise error

    @app.errorhandler(Exception)
    def _unexpected(error):
        app.logger.exception("Unhandled error")
        if request.path.startswith("/api/"):
            return jsonify({"error": {"code": "server_error", "message": f"Something went wrong on the server: {error}"}}), 500
        raise error

    @app.get("/")
    def index():
        return send_from_directory(WEB_DIR, "index.html", max_age=0)

    @app.get("/<path:path>")
    def assets(path):
        if path.startswith("api/"):
            return jsonify({"error": {"code": "not_found", "message": "No such endpoint."}}), 404
        # Static files rarely change between releases and the fonts never do,
        # but a plain restart should always pick up new scripts.
        return send_from_directory(WEB_DIR, path, max_age=0 if path.endswith((".js", ".css", ".html")) else 86400)

    return app
