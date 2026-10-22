"""The JSON API under /api.

Each module registers its routes on the one blueprint below. A route's job is
to read the request, hand it to a repository function together with the
signed-in user (which is where permissions are checked, as in Version 1's
services), and serialize the answer.
"""

from flask import Blueprint, g, jsonify, request, session

from .. import authz, serialize
from ..db import Db
from ..errors import DomainError, NotSignedIn, ValidationError
from ..repos import users as users_repo

bp = Blueprint("api", __name__, url_prefix="/api")


def db() -> Db:
    if "db" not in g:
        g.db = Db()
    return g.db


def current_user() -> dict | None:
    """The signed-in account, re-read from the database on every request so a
    disabled account stops working immediately."""
    if "user" not in g:
        g.user = None
        user_id = session.get("uid")
        if user_id is not None:
            user = users_repo.get_by_id(db(), user_id)
            if user is not None and user["is_active"]:
                g.user = user
            else:
                session.pop("uid", None)
    return g.user


def actor() -> dict:
    """The signed-in user, or a 401."""
    user = current_user()
    if user is None:
        raise NotSignedIn()
    return user


def body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ValidationError("The request body must be a JSON object.")
    return data


def ok(**payload):
    return jsonify(payload or {"ok": True})


def session_payload() -> dict:
    user = current_user()
    return {
        "user": serialize.user(user),
        "permissions": sorted(authz.permissions_for(user["role"])) if user else [],
        "isSetUp": users_repo.is_set_up(db()),
    }


@bp.errorhandler(DomainError)
def _domain_error(error: DomainError):
    return jsonify({"error": {"code": error.code, "message": error.message, **error.data}}), error.status


# Imported for their side effect of registering routes.
from . import assistant, auth, catalog, imports, money, people, sales, stock  # noqa: E402,F401
