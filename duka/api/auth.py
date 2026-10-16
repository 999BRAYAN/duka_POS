"""Session, sign-in, setup and staff accounts."""

from flask import session

from .. import serialize
from ..repos import users as users_repo
from . import actor, bp, body, current_user, db, ok, session_payload


@bp.get("/session")
def get_session():
    return ok(**session_payload())


def _start_session(user: dict) -> None:
    session.clear()
    session["uid"] = user["id"]


@bp.post("/auth/setup")
def setup():
    """First run: creates the manager and signs them straight in."""
    data = body()
    user = users_repo.create_first_manager(
        db(), data.get("username", ""), data.get("password", ""), data.get("fullName", "")
    )
    _start_session(user)
    return ok(**session_payload())


@bp.post("/auth/login")
def login():
    """Signing in — also what "Switch user" calls, with the other account's
    password."""
    data = body()
    user = users_repo.sign_in(db(), (data.get("username") or "").strip(), data.get("password") or "")
    _start_session(user)
    return ok(**session_payload())


@bp.post("/auth/logout")
def logout():
    session.clear()
    return ok()


@bp.post("/auth/password")
def change_password():
    data = body()
    users_repo.change_password(db(), actor(), data.get("userUuid", ""), data.get("newPassword", ""))
    return ok()


@bp.get("/users")
def list_users():
    actor()
    return ok(users=serialize.rows(users_repo.list_users(db()), drop=serialize.USER_DROP))


@bp.post("/users")
def create_user():
    data = body()
    user = users_repo.create_user(
        db(),
        actor(),
        data.get("username", ""),
        data.get("password", ""),
        data.get("fullName", ""),
        data.get("role", "cashier"),
    )
    return ok(user=serialize.user(user))


@bp.post("/users/<uuid>/deactivate")
def deactivate_user(uuid):
    users_repo.deactivate(db(), actor(), uuid)
    return ok()
