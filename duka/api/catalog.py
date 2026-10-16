"""Products, categories and suppliers."""

from .. import serialize
from ..repos import catalog
from . import actor, bp, body, db, ok


@bp.get("/categories")
def list_categories():
    actor()
    return ok(categories=serialize.rows(catalog.list_categories(db())))


@bp.post("/categories")
def add_category():
    data = body()
    category = catalog.add_category(db(), actor(), data.get("name", ""), data.get("description"))
    return ok(category=serialize.row(category))


@bp.get("/products")
def list_products():
    actor()
    return ok(products=serialize.rows(catalog.list_products(db())))


@bp.post("/products")
def add_product():
    data = body()
    product = catalog.add_product(
        db(), actor(), data, confirm_price_below_cost=bool(data.get("confirmPriceBelowCost"))
    )
    return ok(product=serialize.row(product))


@bp.put("/products/<uuid>")
def update_product(uuid):
    data = body()
    product = catalog.update_product(
        db(), actor(), uuid, data, confirm_price_below_cost=bool(data.get("confirmPriceBelowCost"))
    )
    return ok(product=serialize.row(product))


@bp.delete("/products/<uuid>")
def deactivate_product(uuid):
    catalog.deactivate_product(db(), actor(), uuid)
    return ok()


@bp.get("/suppliers")
def list_suppliers():
    actor()
    return ok(suppliers=serialize.rows(catalog.list_suppliers(db())))


@bp.post("/suppliers")
def add_supplier():
    supplier = catalog.add_supplier(db(), actor(), body())
    return ok(supplier=serialize.row(supplier))


@bp.put("/suppliers/<uuid>")
def update_supplier(uuid):
    supplier = catalog.update_supplier(db(), actor(), uuid, body())
    return ok(supplier=serialize.row(supplier))
