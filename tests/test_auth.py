from api_helpers import Client


def test_fresh_install_needs_setup(anon):
    s = anon.get("/api/session").get_json()
    assert s["user"] is None and s["isSetUp"] is False


def test_setup_creates_the_manager_and_signs_in(anon):
    r = anon.post("/api/auth/setup", {"fullName": "Mary", "username": "mary", "password": "secret1"})
    body = r.get_json()
    assert body["user"]["role"] == "manager" and body["isSetUp"] is True
    assert "passwordHash" not in body["user"] and "password_hash" not in body["user"]
    assert anon.get("/api/session").get_json()["user"]["username"] == "mary"


def test_setup_refused_once_a_manager_exists(manager, app):
    r = Client(app).post("/api/auth/setup", {"fullName": "X", "username": "x", "password": "secret1"})
    assert r.status_code == 409 and r.get_json()["error"]["code"] == "manager_exists"


def test_short_password_rejected(anon):
    r = anon.post("/api/auth/setup", {"fullName": "M", "username": "m", "password": "abc"})
    assert r.status_code == 400
    assert r.get_json()["error"]["message"] == "Use at least 6 characters."


def test_wrong_password_and_unknown_user_look_the_same(manager, app):
    c = Client(app)
    a = c.post("/api/auth/login", {"username": "mary", "password": "nope"})
    b = c.post("/api/auth/login", {"username": "ghost", "password": "nope"})
    assert a.status_code == b.status_code == 401
    assert a.get_json() == b.get_json()


def test_only_one_manager_can_exist(manager):
    r = manager.post("/api/users", {"fullName": "Second", "username": "second", "password": "secret1", "role": "manager"})
    assert r.status_code == 409
    assert r.get_json()["error"]["message"].startswith("A manager already exists")


def test_duplicate_username(manager):
    manager.post("/api/users", {"fullName": "A", "username": "dup", "password": "secret1", "role": "cashier"})
    r = manager.post("/api/users", {"fullName": "B", "username": "dup", "password": "secret1", "role": "cashier"})
    assert r.status_code == 409 and r.get_json()["error"]["code"] == "username_taken"


def test_cashier_cannot_manage_staff_or_products(cashier):
    r = cashier.post("/api/users", {"fullName": "Z", "username": "z", "password": "secret1", "role": "cashier"})
    assert r.status_code == 403
    assert r.get_json()["error"]["message"] == "Only a manager can manage staff logins."
    r = cashier.post("/api/products", {"name": "X", "costPrice": 1, "sellingPrice": 2})
    assert r.status_code == 403
    assert "change the product list" in r.get_json()["error"]["message"]


def test_cashier_cannot_open_reports_or_expenses(cashier):
    assert cashier.get("/api/dashboard").status_code == 403
    assert cashier.get("/api/reports/sales").status_code == 403
    assert cashier.get("/api/expenses").status_code == 403
    assert cashier.get("/api/backup").status_code == 403


def test_signed_out_requests_are_401(anon):
    assert anon.get("/api/products").status_code == 401
    assert anon.post("/api/sales", {"cart": []}).status_code == 401


def test_logout(manager):
    manager.post("/api/auth/logout")
    assert manager.get("/api/session").get_json()["user"] is None


def test_disabled_account_cannot_sign_in_and_is_signed_out(manager, cashier, app):
    users = manager.get("/api/users").get_json()["users"]
    carl = next(u for u in users if u["username"] == "carl")
    assert manager.post(f"/api/users/{carl['uuid']}/deactivate").status_code == 200
    # Already-signed-in cashier is cut off immediately...
    assert cashier.get("/api/products").status_code == 401
    # ...and cannot sign back in.
    assert Client(app).post("/api/auth/login", {"username": "carl", "password": "cashpw1"}).status_code == 401


def test_manager_cannot_disable_themselves(manager):
    me = manager.get("/api/session").get_json()["user"]
    assert manager.post(f"/api/users/{me['uuid']}/deactivate").status_code == 400


def test_password_change_own_and_reset_by_manager(manager, cashier, app):
    me = cashier.get("/api/session").get_json()["user"]
    assert cashier.post("/api/auth/password", {"userUuid": me["uuid"], "newPassword": "newpass1"}).status_code == 200
    assert Client(app).post("/api/auth/login", {"username": "carl", "password": "newpass1"}).status_code == 200

    mary = manager.get("/api/session").get_json()["user"]
    # A cashier may not reset the manager's password...
    assert cashier.post("/api/auth/password", {"userUuid": mary["uuid"], "newPassword": "hacked11"}).status_code == 403
    # ...but the manager may reset the cashier's without knowing the old one.
    assert manager.post("/api/auth/password", {"userUuid": me["uuid"], "newPassword": "reset123"}).status_code == 200
    assert Client(app).post("/api/auth/login", {"username": "carl", "password": "reset123"}).status_code == 200


def test_writes_without_the_ajax_header_are_refused(app):
    r = app.test_client().post("/api/auth/login", json={"username": "a", "password": "b"})
    assert r.status_code == 403


def test_v1_password_hashes_still_verify():
    from duka.security import verify_password

    # Produced by Version 1's Dart PasswordHasher for the password "secret1".
    import base64, hashlib

    salt = b"0123456789abcdef"
    key = hashlib.pbkdf2_hmac("sha256", b"secret1", salt, 100000, 32)
    stored = f"pbkdf2_sha256$100000${base64.b64encode(salt).decode()}${base64.b64encode(key).decode()}"
    assert verify_password("secret1", stored) and not verify_password("secret2", stored)
