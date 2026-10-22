"""Bulk import: fill the shop's tables from an Excel (.xlsx) or CSV sheet.

Four kinds of sheet are understood - products, customers, suppliers and
expenses. Columns are found by heading (case, spacing and a few common
alternative names don't matter), so a sheet the shop already keeps usually
imports as it is.

Every row goes through the same repository functions the screens use, so the
same rules apply: permissions, price checks, and above all the stock rule -
stock only ever changes through `stock.record_movement`, so an imported
opening count leaves an audit row like any other adjustment.

A run is always done twice by the browser: first as a preview (everything is
executed inside a transaction that is then rolled back, so the preview is
exactly what the real import will do), then for real.
"""

import csv
import io
import re
from datetime import date, datetime

from . import authz
from .db import Db
from .errors import DomainError, ValidationError
from .repos import catalog, customers, expenses, stock

MAX_ROWS = 5000


class _Rollback(Exception):
    """Raised on purpose to undo a preview."""


def _norm(text) -> str:
    return re.sub(r"[^a-z0-9]", "", str(text or "").lower())


# key, heading shown in the template, accepted headings, required, what to enter
_COLUMNS = {
    "products": [
        ("name", "Name", ["name", "product", "productname", "item", "itemname", "description"], True, "The product's name."),
        ("sku", "SKU", ["sku", "code", "itemcode", "productcode"], False, "Your own stock code. Used to recognise a product that is already in the system."),
        ("barcode", "Barcode", ["barcode", "ean", "upc"], False, "The number under the barcode. Also used to recognise an existing product."),
        ("category", "Category", ["category", "group", "department"], False, "Created automatically if it doesn't exist yet."),
        ("unit", "Unit", ["unit", "uom", "unitofmeasure"], False, "pcs, kg, litre... Blank means pcs."),
        ("costPrice", "Cost price", ["costprice", "cost", "buyingprice", "buyprice", "purchaseprice"], False, "What you pay for one unit."),
        ("sellingPrice", "Selling price", ["sellingprice", "price", "saleprice", "retailprice", "sellprice"], False, "What a customer pays for one unit."),
        ("minSellingPrice", "Minimum price", ["minsellingprice", "minimumprice", "minprice", "floorprice"], False, "Lowest price a cashier may sell at. Blank means the selling price."),
        ("stock", "Stock", ["stock", "quantity", "qty", "openingstock", "onhand", "instock"], False, "How many you have now. For a new product this is the opening stock; for an existing one the stock is corrected to this count."),
        ("reorderLevel", "Reorder level", ["reorderlevel", "reorder", "minstock", "lowstock", "reorderpoint"], False, "Warn when stock falls to this number."),
    ],
    "customers": [
        ("name", "Name", ["name", "customer", "customername", "fullname"], True, "The customer's name."),
        ("phone", "Phone", ["phone", "phonenumber", "mobile", "tel", "telephone", "contact"], False, "Also used to recognise an existing customer."),
        ("email", "Email", ["email", "emailaddress"], False, ""),
        ("address", "Address", ["address", "location"], False, ""),
        ("creditLimit", "Credit limit", ["creditlimit", "limit", "credit"], False, "The most they may owe at once. Blank means no credit."),
    ],
    "suppliers": [
        ("name", "Name", ["name", "supplier", "suppliername", "company"], True, "The supplier's name."),
        ("phone", "Phone", ["phone", "phonenumber", "mobile", "tel", "telephone", "contact"], False, "Also used to recognise an existing supplier."),
        ("email", "Email", ["email", "emailaddress"], False, ""),
        ("address", "Address", ["address", "location"], False, ""),
    ],
    "expenses": [
        ("description", "Description", ["description", "details", "item", "note", "notes", "particulars", "name"], True, "What the money was for."),
        ("amount", "Amount", ["amount", "cost", "total", "value", "price"], True, "How much was spent."),
        ("category", "Category", ["category", "type", "group"], False, "Rent, Transport, Power... Blank means Other."),
        ("date", "Date", ["date", "expensedate", "day"], False, "When it was spent (e.g. 2026-10-22). Blank means today."),
    ],
}

_PERMISSION = {
    "products": authz.MANAGE_PRODUCTS,
    "suppliers": authz.MANAGE_PRODUCTS,
    "customers": authz.MANAGE_CUSTOMERS,
    "expenses": authz.MANAGE_EXPENSES,
}

LABELS = {"products": "Products", "customers": "Customers", "suppliers": "Suppliers", "expenses": "Expenses"}


def kinds() -> list[str]:
    return list(_COLUMNS)


def _spec(kind: str):
    if kind not in _COLUMNS:
        raise ValidationError("Unknown kind of import.")
    return _COLUMNS[kind]


def require_permission(actor: dict, kind: str) -> None:
    _spec(kind)
    authz.require(actor, _PERMISSION[kind])


# --- reading the file ------------------------------------------------------

def _cell(value):
    """A cell as plain text, or a number/date left as it is."""
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def _read_grid(filename: str, data: bytes) -> list[tuple[str, list[list]]]:
    """[(sheet name, rows)] - one entry for a CSV, one per sheet for a workbook."""
    name = (filename or "").lower()
    if name.endswith((".xlsx", ".xlsm")):
        from openpyxl import load_workbook

        try:
            book = load_workbook(io.BytesIO(data), read_only=True, data_only=True)
        except Exception:
            raise ValidationError("That file couldn't be opened as an Excel workbook (.xlsx).") from None
        sheets = []
        for sheet in book.worksheets:
            rows = []
            for row in sheet.iter_rows(values_only=True):
                rows.append([_cell(c) for c in row])
                if len(rows) > MAX_ROWS + 20:
                    raise ValidationError(f"That sheet has more than {MAX_ROWS} rows. Split it into smaller files.")
            sheets.append((sheet.title, rows))
        return sheets
    if name.endswith((".csv", ".txt")):
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = data.decode("cp1252", errors="replace")
        try:
            dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel
        rows = [[_cell(c) for c in r] for r in csv.reader(io.StringIO(text), dialect)]
        return [("CSV", rows)]
    if name.endswith(".xls"):
        raise ValidationError("Old .xls files aren't supported. In Excel choose Save As > Excel Workbook (.xlsx).")
    raise ValidationError("Choose an Excel (.xlsx) or CSV file.")


def _find_header(rows: list[list], spec) -> tuple[int, dict, list[str]] | None:
    """The first of the top rows whose headings include every required column.
    Returns (row index, {key: column index}, unrecognised headings)."""
    required = [k for k, _t, _a, req, _h in spec if req]
    for index, row in enumerate(rows[:15]):
        found, used = {}, set()
        for col, value in enumerate(row):
            token = _norm(value)
            if not token:
                continue
            for key, _title, aliases, _req, _help in spec:
                # An alias never claims a column another, earlier, key took.
                if key not in found and token in aliases:
                    found[key] = col
                    used.add(col)
                    break
        if all(k in found for k in required):
            ignored = [str(v) for c, v in enumerate(row) if v is not None and c not in used]
            return index, found, ignored
    return None


def parse(kind: str, filename: str, data: bytes) -> tuple[list[tuple[int, dict]], list[str]]:
    """[(spreadsheet row number, {key: raw value})] and the headings that were ignored."""
    spec = _spec(kind)
    for _sheet, grid in _read_grid(filename, data):
        located = _find_header(grid, spec)
        if located is None:
            continue
        header_at, columns, ignored = located
        rows = []
        for offset, row in enumerate(grid[header_at + 1:], start=header_at + 2):
            values = {k: (row[c] if c < len(row) else None) for k, c in columns.items()}
            if all(v is None for v in values.values()):
                continue  # blank line
            rows.append((offset, values))
        if len(rows) > MAX_ROWS:
            raise ValidationError(f"That sheet has more than {MAX_ROWS} rows. Split it into smaller files.")
        return rows, ignored
    required = ", ".join(t for _k, t, _a, req, _h in spec if req)
    raise ValidationError(
        f"Couldn't find the column headings for {LABELS[kind].lower()}. "
        f"The first row needs at least: {required}. Download the template to see the layout."
    )


# --- cleaning values -------------------------------------------------------

def _text(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    return str(value).strip() or None


def _number(value, label: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        number = float(value)
    else:
        cleaned = re.sub(r"[^0-9.\-]", "", str(value).replace(",", ""))
        try:
            number = float(cleaned)
        except ValueError:
            raise ValidationError(f"{label} '{value}' isn't a number.") from None
    if number < 0:
        raise ValidationError(f"{label} can't be negative.")
    return number


def _when(value) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return datetime(value.year, value.month, value.day)
    text = str(value).strip()
    for pattern in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%Y/%m/%d"):
        try:
            return datetime.strptime(text, pattern)
        except ValueError:
            pass
    raise ValidationError(f"Date '{text}' isn't recognised. Use a form like 2026-10-22.")


# --- applying one row ------------------------------------------------------

def _same(a, b) -> bool:
    return abs((a or 0) - (b or 0)) < 0.00005


def _category_id(db: Db, actor: dict, name: str | None, cache: dict) -> int | None:
    if not name:
        return None
    key = name.lower()
    if key not in cache:
        row = db.one("SELECT id FROM categories WHERE LOWER(name) = %s", (key,))
        cache[key] = row["id"] if row else catalog.add_category(db, actor, name)["id"]
    return cache[key]


def _find_product(db: Db, sku, barcode, name):
    for column, value in (("sku", sku), ("barcode", barcode)):
        if value:
            row = db.one(f"SELECT * FROM products WHERE {column} = %s ORDER BY is_active DESC LIMIT 1", (value,))
            if row:
                return row
    return db.one("SELECT * FROM products WHERE LOWER(name) = %s ORDER BY is_active DESC LIMIT 1", ((name or "").lower(),))


def _import_product(db, actor, v, state):
    name = _text(v["name"])
    if not name:
        raise ValidationError("The name is empty.")
    sku, barcode = _text(v.get("sku")), _text(v.get("barcode"))
    cost = _number(v.get("costPrice"), "Cost price")
    selling = _number(v.get("sellingPrice"), "Selling price")
    minimum = _number(v.get("minSellingPrice"), "Minimum price")
    count = _number(v.get("stock"), "Stock")
    reorder = _number(v.get("reorderLevel"), "Reorder level")
    category_id = _category_id(db, actor, _text(v.get("category")), state.setdefault("categories", {}))
    unit = _text(v.get("unit"))

    existing = _find_product(db, sku, barcode, name)
    if existing is None:
        data = {
            "name": name, "sku": sku, "barcode": barcode, "categoryId": category_id, "unit": unit,
            "costPrice": cost or 0, "sellingPrice": selling or 0, "minSellingPrice": minimum,
            "reorderLevel": reorder or 0, "stock": 0,
        }
        product = catalog.add_product(db, actor, data, confirm_price_below_cost=True)
        if count:
            stock.record_movement(
                db, product_id=product["id"], type="ADJUSTMENT", quantity=count,
                unit_cost=cost or None, notes="Opening stock (Excel import)", user_id=actor["id"],
            )
        warning = None
        if minimum is not None and cost is not None and minimum < cost:
            warning = "Minimum price is below cost price."
        return "created", name, warning

    # An existing product: only the cells that were filled in change it.
    merged = {
        "name": name,
        "sku": sku if sku else existing["sku"],
        "barcode": barcode if barcode else existing["barcode"],
        "categoryId": category_id if category_id else existing["category_id"],
        "unit": unit or existing["unit"],
        "costPrice": existing["cost_price"] if cost is None else cost,
        "sellingPrice": existing["selling_price"] if selling is None else selling,
        "minSellingPrice": existing["min_selling_price"] if minimum is None else minimum,
        "reorderLevel": existing["reorder_level"] if reorder is None else reorder,
    }
    changes = []
    for label, new, old in (
        ("cost", merged["costPrice"], existing["cost_price"]),
        ("price", merged["sellingPrice"], existing["selling_price"]),
        ("minimum", merged["minSellingPrice"], existing["min_selling_price"]),
        ("reorder", merged["reorderLevel"], existing["reorder_level"]),
    ):
        if not _same(new, old):
            changes.append(label)
    for label, new, old in (
        ("sku", merged["sku"], existing["sku"]), ("barcode", merged["barcode"], existing["barcode"]),
        ("category", merged["categoryId"], existing["category_id"]), ("unit", merged["unit"], existing["unit"]),
        ("name", name, existing["name"]),
    ):
        if new != old:
            changes.append(label)
    if changes:
        catalog.update_product(db, actor, existing["uuid"], merged, confirm_price_below_cost=True)
    note = None
    if count is not None and not _same(count, existing["stock"]):
        stock.record_movement(
            db, product_id=existing["id"], type="ADJUSTMENT", quantity=count - existing["stock"],
            unit_cost=merged["costPrice"] or None,
            notes=f"Stock count from Excel import ({existing['stock']:g} to {count:g})", user_id=actor["id"],
        )
        changes.append("stock")
        note = f"Stock {existing['stock']:g} -> {count:g}."
    if not changes:
        return "unchanged", name, None
    return "updated", name, note or "Changed: " + ", ".join(changes) + "."


def _import_party(table: str, db, actor, v, state):
    """Customers and suppliers share their shape."""
    name = _text(v["name"])
    if not name:
        raise ValidationError("The name is empty.")
    phone = _text(v.get("phone"))
    existing = None
    if phone:
        existing = db.one(f"SELECT * FROM {table} WHERE phone = %s LIMIT 1", (phone,))
    if existing is None:
        existing = db.one(f"SELECT * FROM {table} WHERE LOWER(name) = %s LIMIT 1", (name.lower(),))
    data = {"name": name, "phone": phone, "email": _text(v.get("email")), "address": _text(v.get("address"))}
    if table == "customers":
        data["creditLimit"] = _number(v.get("creditLimit"), "Credit limit")

    if existing is None:
        if table == "customers":
            customers.add_customer(db, actor, {**data, "creditLimit": data["creditLimit"] or 0})
        else:
            catalog.add_supplier(db, actor, data)
        return "created", name, None

    if table == "customers" and existing["is_walk_in"]:
        raise ValidationError("That is the built-in walk-in customer, which can't be changed.")
    merged = {k: (data[k] if data[k] else existing[k]) for k in ("phone", "email", "address")}
    merged["name"] = name
    if table == "customers":
        merged["creditLimit"] = existing["credit_limit"] if data["creditLimit"] is None else data["creditLimit"]
    changed = [k for k in ("name", "phone", "email", "address") if merged[k] != existing[k]]
    if table == "customers" and not _same(merged["creditLimit"], existing["credit_limit"]):
        changed.append("credit limit")
    if not changed:
        return "unchanged", name, None
    if table == "customers":
        customers.update_customer(db, actor, existing["id"], merged)
    else:
        catalog.update_supplier(db, actor, existing["uuid"], merged)
    return "updated", name, "Changed: " + ", ".join(changed) + "."


def _import_expense(db, actor, v, state):
    description = _text(v["description"])
    amount = _number(v.get("amount"), "Amount")
    if not description:
        raise ValidationError("The description is empty.")
    if amount is None:
        raise ValidationError("The amount is empty.")
    when = _when(v.get("date"))
    expense = expenses.add_expense(db, actor, category=_text(v.get("category")) or "", description=description, amount=amount)
    if when is not None:
        db.update("expenses", {"created_at": when}, "id = %s", (expense["id"],))
    return "created", description, None


_ROW_HANDLERS = {
    "products": _import_product,
    "customers": lambda *a: _import_party("customers", *a),
    "suppliers": lambda *a: _import_party("suppliers", *a),
    "expenses": _import_expense,
}


# --- running an import -----------------------------------------------------

def run(db: Db, actor: dict, kind: str, filename: str, data: bytes, *, commit: bool) -> dict:
    """Reads the sheet and applies every valid row. With `commit` False the
    whole run is rolled back at the end, so the report describes what a real
    import would do without changing anything."""
    require_permission(actor, kind)
    parsed, ignored = parse(kind, filename, data)
    if not parsed:
        raise ValidationError("The sheet has headings but no rows underneath them.")
    handler = _ROW_HANDLERS[kind]
    results, counts, state = [], {"created": 0, "updated": 0, "unchanged": 0, "error": 0}, {}

    try:
        with db.tx():
            for number, values in parsed:
                try:
                    # Each row is its own savepoint-free unit: its checks run
                    # before its first write, so a failed row leaves nothing.
                    status, label, note = handler(db, actor, values, state)
                except DomainError as error:
                    status, label, note = "error", _text(values.get("name") or values.get("description")) or "", error.message
                counts[status] += 1
                results.append({"row": number, "status": status, "name": label, "note": note})
            if not commit:
                raise _Rollback()
    except _Rollback:
        pass

    return {
        "kind": kind,
        "committed": commit,
        "counts": counts,
        "total": len(parsed),
        "ignoredColumns": ignored,
        "rows": results,
    }


# --- templates -------------------------------------------------------------

def template(kind: str) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill
    from openpyxl.utils import get_column_letter

    spec = _spec(kind)
    book = Workbook()
    sheet = book.active
    sheet.title = LABELS[kind]
    head_fill = PatternFill("solid", fgColor="FDE68A")
    for col, (_key, title, _aliases, required, _help) in enumerate(spec, start=1):
        cell = sheet.cell(row=1, column=col, value=title)
        cell.font = Font(bold=True)
        cell.fill = head_fill
        sheet.column_dimensions[get_column_letter(col)].width = max(16, len(title) + 4)
    sheet.freeze_panes = "A2"

    guide = book.create_sheet("How to fill")
    guide.append(["Column", "Required", "What to enter"])
    for cell in guide[1]:
        cell.font = Font(bold=True)
    for _key, title, _aliases, required, help_text in spec:
        guide.append([title, "Yes" if required else "No", help_text])
    guide.column_dimensions["A"].width = 20
    guide.column_dimensions["B"].width = 10
    guide.column_dimensions["C"].width = 100
    guide.append([])
    guide.append(["Type your rows on the first sheet, starting under the headings, then upload the file."])
    if kind == "expenses":
        guide.append(["Expenses are never matched to existing ones, so uploading the same sheet twice records them twice."])
    else:
        guide.append(["Rows that match something already in the system update it; only the cells you fill in change."])

    out = io.BytesIO()
    book.save(out)
    return out.getvalue()
