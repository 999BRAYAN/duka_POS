"""Products, categories and suppliers."""

from .. import authz
from ..db import Db, new_uuid, now
from ..errors import NotFound, PriceBelowCost, ValidationError


def _blank_to_none(value):
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def _number(value, label: str, *, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise ValidationError("Prices and quantities must be numbers.") from None
    if number < 0:
        raise ValidationError("Prices and quantities can't be negative.")
    return number


# --- categories -------------------------------------------------------------

def list_categories(db: Db) -> list[dict]:
    return db.all("SELECT * FROM categories ORDER BY name")


def add_category(db: Db, actor: dict, name: str, description: str | None = None) -> dict:
    # Categories are part of the catalog, so they answer to the same
    # permission products do.
    authz.require(actor, authz.MANAGE_PRODUCTS)
    name = (name or "").strip()
    if not name:
        raise ValidationError("Give the category a name.")
    category_id = db.insert(
        "categories",
        {"uuid": new_uuid(), "name": name, "description": _blank_to_none(description), "created_at": now()},
    )
    return db.one("SELECT * FROM categories WHERE id = %s", (category_id,))


# --- products ---------------------------------------------------------------

def list_products(db: Db) -> list[dict]:
    """Active products, by name."""
    return db.all("SELECT * FROM products WHERE is_active = 1 ORDER BY name")


def get_product(db: Db, uuid: str) -> dict:
    product = db.one("SELECT * FROM products WHERE uuid = %s", (uuid,))
    if product is None:
        raise NotFound("That product")
    return product


def _validate_price(cost_price: float, min_selling_price: float, confirmed: bool) -> None:
    if min_selling_price < cost_price and not confirmed:
        raise PriceBelowCost(cost_price, min_selling_price)


def _fields(data: dict) -> dict:
    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("Give the product a name.")
    cost = _number(data.get("costPrice"), "cost price")
    selling = _number(data.get("sellingPrice"), "selling price")
    # Left blank, the floor is the selling price: the common case is a shop
    # that does not haggle, and defaulting to 0 would silently allow giving
    # stock away.
    raw_min = data.get("minSellingPrice")
    min_selling = selling if raw_min in (None, "") else _number(raw_min, "minimum price")
    category_id = data.get("categoryId")
    if category_id is not None and not isinstance(category_id, int):
        raise ValidationError("Unknown category.")
    return {
        "name": name,
        "sku": _blank_to_none(data.get("sku")),
        "barcode": _blank_to_none(data.get("barcode")),
        "category_id": category_id,
        "unit": _blank_to_none(data.get("unit")) or "pcs",
        "cost_price": cost,
        "selling_price": selling,
        "min_selling_price": min_selling,
        "reorder_level": _number(data.get("reorderLevel"), "reorder level"),
    }


def add_product(db: Db, actor: dict, data: dict, *, confirm_price_below_cost: bool = False) -> dict:
    authz.require(actor, authz.MANAGE_PRODUCTS)
    fields = _fields(data)
    opening_stock = _number(data.get("stock"), "opening stock")
    _validate_price(fields["cost_price"], fields["min_selling_price"], confirm_price_below_cost)
    product_id = db.insert(
        "products",
        {"uuid": new_uuid(), **fields, "stock": opening_stock, "created_at": now()},
    )
    return db.one("SELECT * FROM products WHERE id = %s", (product_id,))


def update_product(db: Db, actor: dict, uuid: str, data: dict, *, confirm_price_below_cost: bool = False) -> dict:
    """Edits everything except stock — that moves only through
    `stock.record_movement`, so every change keeps an audit row."""
    authz.require(actor, authz.MANAGE_PRODUCTS)
    existing = get_product(db, uuid)
    fields = _fields(data)
    _validate_price(fields["cost_price"], fields["min_selling_price"], confirm_price_below_cost)
    db.update("products", {**fields, "updated_at": now()}, "id = %s", (existing["id"],))
    return db.one("SELECT * FROM products WHERE id = %s", (existing["id"],))


def deactivate_product(db: Db, actor: dict, uuid: str) -> None:
    """A soft delete: products are referenced by sale and purchase items and
    stock movements, so the row has to stay."""
    authz.require(actor, authz.MANAGE_PRODUCTS)
    existing = get_product(db, uuid)
    db.update("products", {"is_active": 0, "updated_at": now()}, "id = %s", (existing["id"],))


# --- suppliers --------------------------------------------------------------

def list_suppliers(db: Db) -> list[dict]:
    return db.all("SELECT * FROM suppliers ORDER BY name")


def _supplier_fields(data: dict) -> dict:
    name = (data.get("name") or "").strip()
    if not name:
        raise ValidationError("Give the supplier a name.")
    return {
        "name": name,
        "phone": _blank_to_none(data.get("phone")),
        "email": _blank_to_none(data.get("email")),
        "address": _blank_to_none(data.get("address")),
    }


def add_supplier(db: Db, actor: dict, data: dict) -> dict:
    authz.require(actor, authz.MANAGE_PRODUCTS)
    supplier_id = db.insert("suppliers", {"uuid": new_uuid(), **_supplier_fields(data), "created_at": now()})
    return db.one("SELECT * FROM suppliers WHERE id = %s", (supplier_id,))


def update_supplier(db: Db, actor: dict, uuid: str, data: dict) -> dict:
    authz.require(actor, authz.MANAGE_PRODUCTS)
    existing = db.one("SELECT * FROM suppliers WHERE uuid = %s", (uuid,))
    if existing is None:
        raise NotFound("That supplier")
    db.update("suppliers", {**_supplier_fields(data), "updated_at": now()}, "id = %s", (existing["id"],))
    return db.one("SELECT * FROM suppliers WHERE id = %s", (existing["id"],))
