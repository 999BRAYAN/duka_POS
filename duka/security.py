"""Password hashing — PBKDF2-HMAC-SHA256.

The stored string is byte-for-byte the format Version 1 wrote, so accounts
carry across if a shop moves its data over:

    pbkdf2_sha256$<iterations>$<base64 salt>$<base64 hash>

The iteration count travels with each hash, so it can be raised later without
invalidating existing passwords.
"""

import base64
import hashlib
import hmac
import os

_ALGORITHM = "pbkdf2_sha256"
_ITERATIONS = 100_000
_SALT_BYTES = 16
_KEY_BYTES = 32


def hash_password(password: str) -> str:
    salt = os.urandom(_SALT_BYTES)
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS, _KEY_BYTES)
    return f"{_ALGORITHM}${_ITERATIONS}${base64.b64encode(salt).decode()}${base64.b64encode(key).decode()}"


def _decode(stored: str):
    parts = stored.split("$")
    if len(parts) != 4 or parts[0] != _ALGORITHM:
        return None
    try:
        iterations = int(parts[1])
        if iterations <= 0:
            return None
        return iterations, base64.b64decode(parts[2]), base64.b64decode(parts[3])
    except (ValueError, base64.binascii.Error):
        return None


def verify_password(password: str, stored: str) -> bool:
    """False for anything unparseable rather than raising — a malformed row
    must read as "wrong password", never as a crash on the login screen."""
    decoded = _decode(stored)
    if decoded is None:
        return False
    iterations, salt, key = decoded
    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations, len(key))
    return hmac.compare_digest(actual, key)


# Verified against when a username doesn't exist, so a missing account takes
# as long to reject as a wrong password and doesn't reveal which exist.
DUMMY_HASH = hash_password("no such user")
