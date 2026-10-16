"""Domain errors.

Every message here is the same text Version 1 showed, because the screens
display them verbatim. `code` lets the browser react to a specific refusal
(for example offering a credit-limit override) without parsing prose.
"""


def money(value: float) -> str:
    """Dart's `toStringAsFixed(2)`."""
    return f"{value:.2f}"


class DomainError(Exception):
    status = 400
    code = "error"

    def __init__(self, message: str, **data):
        super().__init__(message)
        self.message = message
        self.data = data


class ValidationError(DomainError):
    code = "invalid"


class NotFound(DomainError):
    status = 404
    code = "not_found"

    def __init__(self, what: str = "That record"):
        super().__init__(f"{what} could not be found.")


class NotSignedIn(DomainError):
    status = 401
    code = "not_signed_in"

    def __init__(self):
        super().__init__("Sign in to continue.")


# --- authorization -------------------------------------------------------

_UNAUTHORIZED = {
    "manageProducts": "Only a manager can change the product list. Ask them to add or edit this.",
    "adjustStock": "Only a manager can correct stock counts. Ask them to make this change.",
    "receiveStock": "Only a manager can receive stock from a supplier.",
    "processSale": "You are not allowed to complete sales.",
    "manageCustomers": "Only a manager can change customer accounts or record payments.",
    "overrideCreditLimit": "Only a manager can approve a sale beyond a customer's credit limit.",
    "manageExpenses": "Only a manager can record shop expenses.",
    "voidSale": "Only a manager can void a completed sale.",
    "manageStaff": "Only a manager can manage staff logins.",
}


class Unauthorized(DomainError):
    status = 403
    code = "unauthorized"

    def __init__(self, permission: str):
        super().__init__(_UNAUTHORIZED[permission], permission=permission)


# --- users ---------------------------------------------------------------

class InvalidCredentials(DomainError):
    status = 401
    code = "invalid_credentials"

    def __init__(self):
        super().__init__("That username and password don't match. Check the password and try again.")


class ManagerAlreadyExistsForSetup(DomainError):
    status = 409
    code = "manager_exists"

    def __init__(self):
        super().__init__("This shop already has a manager account. Sign in instead.")


class ManagerAlreadyExists(DomainError):
    status = 409
    code = "manager_exists"

    def __init__(self):
        super().__init__("A manager already exists; only one user may hold the manager role at a time.")


class UsernameTaken(DomainError):
    status = 409
    code = "username_taken"

    def __init__(self):
        super().__init__("That username is already taken.")


class WeakPassword(DomainError):
    code = "weak_password"

    def __init__(self, minimum_length: int):
        super().__init__(f"Use at least {minimum_length} characters.", minimumLength=minimum_length)


# --- products / customers / inventory -------------------------------------

class PriceBelowCost(DomainError):
    status = 409
    code = "price_below_cost"

    def __init__(self, cost_price: float, min_selling_price: float):
        super().__init__(
            f"Minimum selling price ({min_selling_price}) is below cost price ({cost_price}).",
            costPrice=cost_price,
            minSellingPrice=min_selling_price,
        )


class WalkInCustomerNotEditable(DomainError):
    status = 409
    code = "walk_in_not_editable"

    def __init__(self):
        super().__init__("The walk-in customer cannot be edited.")


class MissingAdjustmentReason(DomainError):
    code = "missing_adjustment_reason"

    def __init__(self):
        super().__init__("A reason is required for a manual stock adjustment.")


# --- sales ----------------------------------------------------------------

class PriceBelowFloor(DomainError):
    status = 409
    code = "price_below_floor"

    def __init__(self, product_name: str, effective_price: float, min_selling_price: float):
        super().__init__(
            f"'{product_name}' would sell at {money(effective_price)} after discount, "
            f"below its minimum selling price of {money(min_selling_price)}."
        )


class InsufficientStock(DomainError):
    status = 409
    code = "insufficient_stock"

    def __init__(self, product_name: str, requested: float, available: float):
        super().__init__(
            f"Only {money(available)} of '{product_name}' left in stock, "
            f"but {money(requested)} were requested."
        )


class CustomerRequiredForCredit(DomainError):
    code = "customer_required"

    def __init__(self):
        super().__init__("A customer is required for payment method 'credit'.")


class MissingVoidReason(DomainError):
    code = "missing_void_reason"

    def __init__(self):
        super().__init__("Say why this sale is being voided.")


class SaleAlreadyVoid(DomainError):
    status = 409
    code = "already_void"

    def __init__(self, invoice_number: str):
        super().__init__(f"Sale {invoice_number} has already been voided.")


class CreditLimitExceeded(DomainError):
    status = 409
    code = "credit_limit_exceeded"

    def __init__(self, customer_name: str, would_be_balance: float, credit_limit: float):
        super().__init__(
            f"This sale would take {customer_name}'s balance to {money(would_be_balance)}, "
            f"over their credit limit of {money(credit_limit)}."
        )


# --- purchases ------------------------------------------------------------

class InvalidPurchaseStatus(DomainError):
    status = 409
    code = "invalid_purchase_status"


class InvalidPaymentStatus(DomainError):
    code = "invalid_payment_status"


class InvalidPurchasePayment(DomainError):
    code = "invalid_purchase_payment"


# --- backup ---------------------------------------------------------------

class InvalidBackup(DomainError):
    code = "invalid_backup"
