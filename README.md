# duka_pos — Version 3

This branch (`v3`) is **Version 3** of duka_pos: the same point-of-sale system as
Version 1 — same screens, same rules, same look — rebuilt as

| Layer      | Version 1                      | **Version 3**                          |
|------------|--------------------------------|----------------------------------------|
| Front end  | Flutter (Dart), compiled to web| **HTML + CSS + JavaScript** (no build step) |
| Back end   | none (runs in the browser)     | **Python** (Flask)                     |
| Database   | SQLite (Drift), in the browser | **MySQL**                              |

Versions 1 and 2 live on the `v1` and `v2` branches and are untouched.

## What changed, and what deliberately didn't

Everything a person can do in v1 can be done here, with the same wording and
the same rules: roles and permissions (admin/manager/cashier), the one-manager
rule, products with price floors and below-cost confirmation, the two-step
sale (build the order → confirm & pay), held orders, credit sales with
credit limits and manager override, voiding, customer statements and payments,
goods received with weighted-average cost, supplier balances, expenses, stock
adjustments with mandatory reasons, dashboard, sales / profit & loss /
inventory reports, PDF and CSV exports, receipts, backup/restore, light/dark
themes. The 12 tables are the same ones as v1's schema (v7).

What necessarily differs because the data now lives on a server:

* **One shared database.** Every till that opens the page sees the same stock
  and balances (v1 kept a separate database in each browser). Lists refresh
  every 10 seconds, and stock changes are row-locked so two tills can't sell
  the last unit twice.
* **Sessions are cookies**, so a page reload keeps you signed in (v1 signed you
  out on reload). Permissions are enforced on the server as well as in the UI.
* **Backup is a JSON file** of every table (v1 downloaded the SQLite file).
  Restore replaces the whole database in one transaction.
* **PDFs are made by the server** (ReportLab) instead of in the browser.
* "One manager" is enforced by a unique index over a generated column (MySQL has
  no partial indexes). Money is `DECIMAL(15,4)`, not floating point.
* Password hashes use v1's exact format, so v1 accounts verify unchanged.

## Setting it up (Windows, XAMPP)

1. Start **MySQL** from the XAMPP control panel.
2. Install Python 3.11+ and the dependencies:
   ```
   py -m pip install -r requirements.txt
   ```
3. (Optional) `copy .env.example .env` and edit the database settings.
4. Run it — the database and tables are created on first start:
   ```
   py run.py
   ```
   or double-click `start.bat`. Open <http://127.0.0.1:8080>.
5. The first visit asks you to create the manager account.

To let other tills on the shop network use it, set `DUKA_HOST=0.0.0.0` and open
`http://<this-pc's-address>:8080` from them.

## Layout

```
duka/            Python back end
  repos/         the business rules (sales, stock, credit, purchases, reports…)
  api/           the JSON routes
  exports.py     receipt, report and CSV output
schema.sql       the MySQL schema
init_db.py       creates the database + tables (run.py does this for you)
web/             the front end: index.html, css/, js/ (one file per screen), fonts/
tests/           API tests (pytest) and tests/e2e browser tests (Playwright + Chrome)
```

## Tests

Point them at a scratch database (they empty it!):

```
py -m pip install -r requirements-dev.txt
set DUKA_DB_NAME=duka_pos_test
py -m pytest tests            # API + business rules
py -m pytest tests/e2e        # clicks through the real UI in Chrome
```
