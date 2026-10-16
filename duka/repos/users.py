"""Accounts and signing in (Version 1's UserRepository + AuthService)."""

import pymysql

from .. import authz
from ..db import Db, new_uuid, now
from ..errors import (
    InvalidCredentials,
    ManagerAlreadyExists,
    ManagerAlreadyExistsForSetup,
    NotFound,
    UsernameTaken,
    ValidationError,
    WeakPassword,
)
from ..security import DUMMY_HASH, hash_password, verify_password

# Short enough not to fight a shopkeeper at a counter, long enough that a
# four-digit PIN doesn't slip through.
MINIMUM_PASSWORD_LENGTH = 6
ROLES = ("admin", "manager", "cashier")


def get_by_username(db: Db, username: str) -> dict | None:
    return db.one("SELECT * FROM users WHERE username = %s", (username,))


def get_by_id(db: Db, user_id: int) -> dict | None:
    return db.one("SELECT * FROM users WHERE id = %s", (user_id,))


def get_by_uuid(db: Db, uuid: str) -> dict | None:
    return db.one("SELECT * FROM users WHERE uuid = %s", (uuid,))


def list_users(db: Db) -> list[dict]:
    return db.all("SELECT * FROM users ORDER BY full_name")


def has_manager(db: Db) -> bool:
    return db.scalar("SELECT COUNT(*) FROM users WHERE role = 'manager' AND is_active = 1") > 0


def is_set_up(db: Db) -> bool:
    """Whether anyone can sign in yet. False on a brand-new install, which is
    what sends the app to first-run setup instead of the login screen."""
    return has_manager(db)


def _assert_strong_enough(password: str) -> None:
    if len(password) < MINIMUM_PASSWORD_LENGTH:
        raise WeakPassword(MINIMUM_PASSWORD_LENGTH)


def _insert_user(db: Db, username: str, password_hash: str, full_name: str, role: str) -> dict:
    if role not in ROLES:
        raise ValidationError("Unknown role.")
    try:
        user_id = db.insert(
            "users",
            {
                "uuid": new_uuid(),
                "username": username,
                "password_hash": password_hash,
                "full_name": full_name,
                "role": role,
                "created_at": now(),
            },
        )
    except pymysql.err.IntegrityError as e:
        message = str(e)
        if "idx_single_manager" in message:
            raise ManagerAlreadyExists() from e
        if "username" in message:
            raise UsernameTaken() from e
        raise
    return get_by_id(db, user_id)


def _create(db: Db, username: str, password: str, full_name: str, role: str) -> dict:
    _assert_strong_enough(password)
    return _insert_user(db, username.strip(), hash_password(password), full_name.strip(), role)


def sign_in(db: Db, username: str, password: str) -> dict:
    """Verifies the credentials and returns the user row.

    One error for both "no such username" and "wrong password": telling them
    apart would let anyone discover which usernames exist."""
    user = get_by_username(db, username)
    if user is None:
        verify_password(password, DUMMY_HASH)
        raise InvalidCredentials()
    if not user["is_active"]:
        raise InvalidCredentials()
    if not verify_password(password, user["password_hash"]):
        raise InvalidCredentials()
    return user


def create_first_manager(db: Db, username: str, password: str, full_name: str) -> dict:
    """Creates the shop's one manager account on a fresh install."""
    if not username.strip() or not full_name.strip():
        raise ValidationError("Enter your name and a username.")
    if has_manager(db):
        raise ManagerAlreadyExistsForSetup()
    return _create(db, username, password, full_name, "manager")


def create_user(db: Db, actor: dict, username: str, password: str, full_name: str, role: str) -> dict:
    authz.require(actor, authz.MANAGE_STAFF)
    if not username.strip() or not full_name.strip():
        raise ValidationError("Enter a name and a username.")
    return _create(db, username, password, full_name, role)


def change_password(db: Db, actor: dict, user_uuid: str, new_password: str) -> None:
    """Replaces a password. Anyone may change their own; a manager can reset
    anyone's without knowing the old one — the only way to recover an account
    when nothing can email a reset link."""
    target = get_by_uuid(db, user_uuid)
    if target is None:
        raise NotFound("That account")
    if actor is None or (actor["id"] != target["id"] and not authz.can(actor, authz.MANAGE_STAFF)):
        authz.require(actor, authz.MANAGE_STAFF)
    _assert_strong_enough(new_password)
    db.update(
        "users",
        {"password_hash": hash_password(new_password), "updated_at": now()},
        "id = %s",
        (target["id"],),
    )


def deactivate(db: Db, actor: dict, user_uuid: str) -> None:
    authz.require(actor, authz.MANAGE_STAFF)
    target = get_by_uuid(db, user_uuid)
    if target is None:
        raise NotFound("That account")
    # Disabling your own account would leave nobody able to sign in — the
    # manager role is unique, so there is no second manager to undo it.
    if target["id"] == actor["id"]:
        raise ValidationError("You can't disable the account you're signed in with.")
    db.update("users", {"is_active": 0, "updated_at": now()}, "id = %s", (target["id"],))
