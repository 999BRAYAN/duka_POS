"""Expenses, the dashboard, reports and backups."""

from flask import Response, request

from .. import authz, dates, exports, serialize
from ..errors import ValidationError
from ..repos import backup, expenses, reports
from . import actor, bp, body, db, ok


@bp.get("/expenses")
def list_expenses():
    authz.require(actor(), authz.MANAGE_EXPENSES)
    return ok(expenses=serialize.rows(expenses.list_expenses(db())))


@bp.post("/expenses")
def add_expense():
    data = body()
    expense = expenses.add_expense(
        db(),
        actor(),
        category=data.get("category", ""),
        description=data.get("description", ""),
        amount=data.get("amount"),
    )
    return ok(expense=serialize.row(expense))


# The dashboard and reports sit behind the same permission the navigation
# uses for them: the one that manages the catalog.

@bp.get("/dashboard")
def dashboard():
    authz.require(actor(), authz.MANAGE_PRODUCTS)
    return ok(**reports.dashboard(db()))


def _range():
    period = request.args.get("period", "today")
    if period not in dates.PERIODS:
        raise ValidationError("Unknown report period.")
    start, end = dates.for_period(period)
    return period, start, end


def _download(data: bytes, filename: str, mimetype: str) -> Response:
    return Response(data, mimetype=mimetype, headers={"Content-Disposition": f'attachment; filename="{filename}"'})


def _report(name: str, build, csv_name: str, make_csv, make_pdf):
    authz.require(actor(), authz.MANAGE_PRODUCTS)
    period, start, end = _range()
    report = build(db(), start, end)
    fmt = request.args.get("format", "json")
    label = f"{csv_name}_{exports.range_stamp(start, end)}"
    if fmt == "csv":
        return _download(make_csv(report, start, end), f"{label}.csv", "text/csv")
    if fmt == "pdf":
        return _download(make_pdf(report, start, end), f"{label}.pdf", "application/pdf")
    return ok(period=period, start=start.isoformat(timespec="milliseconds"), end=end.isoformat(timespec="milliseconds"), report=report)


@bp.get("/reports/sales")
def sales_report():
    return _report("sales", reports.sales_report, "sales_report", exports.sales_report_csv, exports.sales_report_pdf)


@bp.get("/reports/pnl")
def pnl_report():
    return _report("pnl", reports.profit_and_loss_report, "profit_and_loss", exports.pnl_csv, exports.pnl_pdf)


@bp.get("/reports/inventory")
def inventory_report():
    return _report("inventory", reports.inventory_report, "inventory_report", exports.inventory_csv, exports.inventory_pdf)


# --- backup -----------------------------------------------------------------------

@bp.get("/backup")
def download_backup():
    authz.require(actor(), authz.MANAGE_PRODUCTS)
    data = backup.export_all(db())
    return _download(data, f"duka_pos_backup_{exports.stamp()}.json", "application/json")


@bp.post("/restore")
def restore_backup():
    authz.require(actor(), authz.MANAGE_STAFF)
    upload = request.files.get("file")
    if upload is None:
        raise ValidationError("Choose a backup file.")
    counts = backup.restore_all(db(), upload.read())
    return ok(restored=counts)
