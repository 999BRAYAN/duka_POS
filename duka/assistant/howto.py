""""How do I...?" - plain directions for using the app itself.

Wording follows the menu: Selling / Stock / People / Money.
"""

import re

from .common import Ctx, answer

# (words that point at it, title, steps)
TOPICS = [
    (r"\bvoid|cancel (a |the )?sale|undo (a |the )?sale|wrong sale|refund",
     "Void a sale",
     "Menu > Sales history, find the sale and press Void sale, then give a reason. Stock goes back on the shelf and any credit it added to a customer is reversed. A manager does this; a voided sale never counts in reports."),
    (r"\bhold\b|park (a |the )?(sale|order)|resume",
     "Hold an order",
     "On New sale, press Hold order to put the cart aside while you serve someone else. The pause icon at the top of the screen (Held orders) lists them so you can resume one."),
    (r"credit sale|sell on credit|on credit|customer pay later|pay later",
     "Sell on credit",
     "Menu > New sale, build the order and Review order. Pick the customer, then choose Credit as the payment method (or take part payment) - whatever isn't paid goes onto the customer's balance, up to their credit limit. A manager can override the limit."),
    (r"credit limit",
     "Credit limits",
     "Each customer has a credit limit (Menu > Customers). A sale that would push them past it is refused unless a manager overrides it."),
    (r"(receive|record|collect|take) (a )?(customer )?payment|customer (is )?paying|pay(ing)? (off|back) (a |their )?(debt|balance|credit)",
     "Take a payment from a customer",
     "Menu > Customers, use the Receive payment action on their row, enter the amount and how they paid (cash, M-Pesa or card). Their balance drops (never below zero) and it shows on their statement."),
    (r"statement|ledger",
     "A customer's statement",
     "Menu > Customers, press the Statement icon on their row to see every credit sale and payment with a running balance."),
    (r"(add|new|create|register) (a )?(new )?customer",
     "Add a customer",
     "Menu > Customers > Add customer. Give a name, phone, email, address and a credit limit (0 means no credit)."),
    (r"(add|new|create) (a )?(new )?product|new item|add item|register (a )?product",
     "Add a product",
     "Menu > Products, press the Add product icon at the top. Fill in the name, cost, selling price, the lowest price you will accept, opening stock and the level to warn you at; if a price is below cost you'll be asked to confirm. A manager can do this."),
    (r"(change|edit|update) (the )?(price|cost)|reprice",
     "Change a price",
     "Menu > Products, press Edit on the product's row and change its selling or lowest price. Only a manager can."),
    (r"receive stock|goods received|new stock|restock|record (a )?purchase|buy stock|supplier delivery|delivery",
     "Receive stock from a supplier",
     "Menu > Receive stock. Pick the supplier, add each product with the quantity and what you paid per unit, and say whether it is paid, part-paid or on credit. Stock goes up and the average cost is updated. If it was on credit, use Record payment on that purchase later."),
    (r"pay (a |the )?supplier|supplier payment|record payment.*purchase",
     "Pay a supplier",
     "Menu > Receive stock, find the purchase and press Record payment, then enter the amount."),
    (r"adjust|stock count|stocktake|stock take|damaged|expired|shrinkage|correct (the )?stock|wrong stock",
     "Correct stock (count, damage, loss)",
     "Menu > Stock adjustments. Choose the product and the change (+ or -). A reason is required and is kept as an audit record."),
    (r"\bexpense",
     "Record an expense",
     "Menu > Expenses > Add expense: category, description and amount. Expenses reduce net profit in the reports."),
    (r"import|upload|bulk|spreadsheet|from excel",
     "Import from Excel",
     "Menu > Import from Excel. Choose the kind (products, customers, suppliers or expenses) and your .xlsx or .csv file. You get a preview first - nothing is saved until you confirm. Columns are found by their headings."),
    (r"\breport|\bexport|download|pdf|csv|print",
     "Reports and exports",
     "Menu > Reports. Pick Today / This week / This month / This year, then use the PDF or CSV (Excel) buttons. Sales history also has PDF and CSV downloads, and receipts can be printed after a sale."),
    (r"back ?up|restore|save (my )?data|lose (my )?data",
     "Back up and restore",
     "On the Dashboard press Backup now - it downloads a file of all your data; keep copies off this computer. Restore from backup (next to it) replaces everything with a backup file, after saving a safety copy first."),
    (r"(add|new|create) (a )?(new )?(cashier|user|staff|login|account|employee)|staff login|new employee",
     "Add a staff login",
     "Menu > Staff logins > Add staff. A cashier can only ring up sales; a manager has full access. Only one manager account may exist at a time."),
    (r"password",
     "Change your password",
     "Open the menu and choose Change password. A manager can reset anyone's from Staff logins (Reset password)."),
    (r"switch user|sign out|log ?out|change user|another user",
     "Switch user or sign out",
     "Open the menu and choose Switch user (or Sign out) at the bottom."),
    (r"dark mode|theme|light mode|colou?r",
     "Light and dark theme",
     "Open the menu and pick Light, Match the device or Dark."),
    (r"stock health|slow mover|dead stock|insight",
     "Stock health",
     "Menu > Stock health shows every product as fast, steady, slow, over-stocked, not selling or needing reorder, with days of cover, suggested order quantities and money tied up. It gets more accurate after a week or two of sales."),
    (r"barcode|scan",
     "Barcodes",
     "Give a product a barcode on its Products form, then type or scan it into the search box on New sale (it searches name, SKU and barcode) to find it and add it to the cart."),
    (r"dashboard",
     "Dashboard",
     "Menu > Dashboard shows today's takings, profit, low stock and who owes you, plus a 7-day trend. Managers only."),
    (r"supplier",
     "Suppliers",
     "Menu > Suppliers lists them with what you owe each. Add one there, or while receiving stock."),
]

_GENERIC = r"\b(how (do|can|should|to)|where (do|can|is)|can i|steps|guide|show me how|teach)\b"


def is_howto(q: str) -> bool:
    return bool(re.search(_GENERIC, q))


def lookup(q: str) -> dict | None:
    for pattern, title, steps in TOPICS:
        if re.search(pattern, q):
            return answer(f"{title}: {steps}")
    return None


def topic_list() -> dict:
    return answer("I can walk you through: " + ", ".join(t for _, t, _ in TOPICS[:16]) + ". Ask, for example, \"how do I receive stock?\".")
