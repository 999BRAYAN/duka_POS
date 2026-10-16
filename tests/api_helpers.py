"""Helpers shared by the API tests."""


class Client:
    """A browser stand-in: a cookie jar plus JSON helpers."""

    def __init__(self, app):
        self.http = app.test_client()

    def call(self, method, path, json=None, **kwargs):
        response = self.http.open(path, method=method, json=json, headers={"X-Requested-With": "duka"}, **kwargs)
        return response

    def get(self, path, **kw):
        return self.call("GET", path, **kw)

    def post(self, path, json=None, **kw):
        if "data" in kw:  # multipart upload
            return self.call("POST", path, json=None, **kw)
        return self.call("POST", path, json=json or {}, **kw)

    def put(self, path, json=None, **kw):
        return self.call("PUT", path, json=json or {}, **kw)

    def delete(self, path, **kw):
        return self.call("DELETE", path, **kw)


def make_product(client, name="Elbow", cost=10, price=15, minimum=None, stock=100, reorder=5, **extra):
    body = {"name": name, "costPrice": cost, "sellingPrice": price, "stock": stock, "reorderLevel": reorder, **extra}
    if minimum is not None:
        body["minSellingPrice"] = minimum
    r = client.post("/api/products", body)
    assert r.status_code == 200, r.get_json()
    return r.get_json()["product"]


def make_customer(client, name="Jane", limit=1000):
    r = client.post("/api/customers", {"name": name, "creditLimit": limit})
    assert r.status_code == 200, r.get_json()
    return r.get_json()["customer"]


def sell(client, lines, **kw):
    cart = [{"productId": p["id"], "price": price if price is not None else p["sellingPrice"], "quantity": q} for p, q, price in lines]
    return client.post("/api/sales", {"cart": cart, **kw})


def get_customer(client, customer_id):
    return next(c for c in client.get("/api/customers").get_json()["customers"] if c["id"] == customer_id)


def get_product(client, uuid):
    return next(p for p in client.get("/api/products").get_json()["products"] if p["uuid"] == uuid)
