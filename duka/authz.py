"""Roles and permissions — the same table Version 1 used.

Roles come from the `users.role` column (admin, manager, cashier). A cashier
holds exactly one permission: ringing up a sale.
"""

from .errors import NotSignedIn, Unauthorized

MANAGE_PRODUCTS = "manageProducts"
ADJUST_STOCK = "adjustStock"
RECEIVE_STOCK = "receiveStock"
PROCESS_SALE = "processSale"
MANAGE_CUSTOMERS = "manageCustomers"
OVERRIDE_CREDIT_LIMIT = "overrideCreditLimit"
MANAGE_EXPENSES = "manageExpenses"
VOID_SALE = "voidSale"
MANAGE_STAFF = "manageStaff"

_FULL_ACCESS = frozenset(
    {
        MANAGE_PRODUCTS,
        ADJUST_STOCK,
        RECEIVE_STOCK,
        PROCESS_SALE,
        MANAGE_CUSTOMERS,
        OVERRIDE_CREDIT_LIMIT,
        MANAGE_EXPENSES,
        MANAGE_STAFF,
        VOID_SALE,
    }
)

ROLE_PERMISSIONS = {
    "admin": _FULL_ACCESS,
    "manager": _FULL_ACCESS,
    # Cashiers can't touch the catalog, inventory, or purchasing, but ringing
    # up a sale is their job — this is the one permission they hold.
    "cashier": frozenset({PROCESS_SALE}),
}


def permissions_for(role: str | None) -> frozenset:
    return ROLE_PERMISSIONS.get(role or "", frozenset())


def can(user: dict | None, permission: str) -> bool:
    if user is None:
        return False
    return permission in permissions_for(user["role"])


def require(user: dict | None, permission: str) -> None:
    """Raises if nobody is signed in, or if the signed-in user lacks
    `permission`."""
    if user is None:
        raise NotSignedIn()
    if permission not in permissions_for(user["role"]):
        raise Unauthorized(permission)
