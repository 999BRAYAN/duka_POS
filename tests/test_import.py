"""Bulk import from Excel / CSV sheets."""

import io

from openpyxl import Workbook


def sheet(rows, title="Sheet1"):
    book = Workbook()
    ws = book.active
    ws.title = title
    for r in rows:
        ws.append(r)
    out = io.BytesIO()
    book.save(out)
    return out.getvalue()


def upload(client, kind, data, filename="s.xlsx", commit=False):
    return client.post(
        f"/api/import/{kind}",
        data={"file": (io.BytesIO(data), filename), "commit": "1" if commit else "0"},
        content_type="multipart/form-data",
    )


PRODUCTS = [
    ["Product", "Code", "Category", "Buying Price", "Price", "Qty"],
    ["Elbow 1/2", "EL12", "Plumbing", 10, 15, 40],
    ["Tap", "TP1", "Plumbing", "1,200", "KES 1,500", 5],
    [None, None, None, None, None, None],
    ["Broken", "B1", None, "abc", 5, 1],
]


def test_preview_changes_nothing_and_commit_populates(manager):
    r = upload(manager, "products", sheet(PRODUCTS))
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body["counts"] == {"created": 2, "updated": 0, "unchanged": 0, "error": 1}
    assert not body["committed"]
    assert manager.get("/api/products").get_json()["products"] == []
    assert manager.get("/api/categories").get_json()["categories"] == []

    r = upload(manager, "products", sheet(PRODUCTS), commit=True)
    assert r.get_json()["counts"]["created"] == 2
    products = {p["name"]: p for p in manager.get("/api/products").get_json()["products"]}
    assert set(products) == {"Elbow 1/2", "Tap"}
    assert products["Tap"]["costPrice"] == 1200 and products["Tap"]["sellingPrice"] == 1500
    assert products["Elbow 1/2"]["stock"] == 40
    assert len(manager.get("/api/categories").get_json()["categories"]) == 1


def test_reimport_updates_by_sku_and_corrects_stock(manager):
    upload(manager, "products", sheet(PRODUCTS), commit=True)
    again = [["Name", "SKU", "Price", "Stock"], ["Elbow half inch", "EL12", 18, 35]]
    body = upload(manager, "products", sheet(again), commit=True).get_json()
    assert body["counts"]["updated"] == 1 and body["counts"]["created"] == 0
    p = next(p for p in manager.get("/api/products").get_json()["products"] if p["sku"] == "EL12")
    assert p["sellingPrice"] == 18 and p["stock"] == 35 and p["costPrice"] == 10
    # Running the same sheet again changes nothing.
    assert upload(manager, "products", sheet(again), commit=True).get_json()["counts"]["unchanged"] == 1


def test_csv_customers_suppliers_expenses(manager):
    csv_customers = b"Name;Phone;Credit Limit\nJane;0712;5000\nJohn;0722;\n"
    r = upload(manager, "customers", csv_customers, "c.csv", commit=True)
    assert r.get_json()["counts"]["created"] == 2
    jane = next(c for c in manager.get("/api/customers").get_json()["customers"] if c["name"] == "Jane")
    assert jane["creditLimit"] == 5000

    r = upload(manager, "suppliers", sheet([["Supplier", "Tel"], ["Pipes Ltd", "0733"]]), commit=True)
    assert r.get_json()["counts"]["created"] == 1

    r = upload(manager, "expenses", sheet([["Details", "Amount", "Type", "Date"], ["Rent", 20000, "Rent", "2026-03-01"]]), commit=True)
    assert r.get_json()["counts"]["created"] == 1
    e = manager.get("/api/expenses").get_json()["expenses"][0]
    assert e["amount"] == 20000 and e["createdAt"].startswith("2026-03-01")


def test_bad_files_and_permissions(manager, cashier):
    r = upload(manager, "products", sheet([["Foo", "Bar"], [1, 2]]))
    assert r.status_code == 400 and "headings" in r.get_json()["error"]["message"]
    assert upload(manager, "products", b"x", "a.xls").status_code == 400
    assert upload(manager, "nonsense", sheet(PRODUCTS)).status_code == 400
    assert upload(cashier, "products", sheet(PRODUCTS)).status_code == 403
    assert cashier.get("/api/import/products/template").status_code == 403
    t = manager.get("/api/import/products/template")
    assert t.status_code == 200 and t.data[:2] == b"PK"
    # The blank template itself has no rows to import.
    assert upload(manager, "products", t.data).status_code == 400
