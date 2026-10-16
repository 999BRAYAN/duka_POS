"""What the shop spends that isn't stock: rent, transport, power, licences."""

from .. import authz
from ..db import Db, new_uuid, now
from ..errors import ValidationError


def list_expenses(db: Db) -> list[dict]:
    return db.all("SELECT * FROM expenses ORDER BY created_at DESC, id DESC")


def add_expense(db: Db, actor: dict, *, category: str, description: str, amount) -> dict:
    authz.require(actor, authz.MANAGE_EXPENSES)
    try:
        amount = float(amount)
    except (TypeError, ValueError):
        amount = 0.0
    if amount <= 0:
        raise ValidationError("Enter how much was spent.")
    description = (description or "").strip()
    if not description:
        raise ValidationError("Say what the money was for.")
    category = (category or "").strip() or "Other"

    expense_id = db.insert(
        "expenses",
        {
            "uuid": new_uuid(),
            "category": category,
            "description": description,
            "amount": amount,
            "user_id": actor["id"],
            "created_at": now(),
        },
    )
    return db.one("SELECT * FROM expenses WHERE id = %s", (expense_id,))
