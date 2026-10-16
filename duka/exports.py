"""CSV and PDF output: the receipt, the reports, and the sales history.

The documents are laid out the way Version 1's were. Text is kept to what the
PDF's built-in Helvetica can draw (Latin-1), which is also why separators are
plain hyphens and " | " rather than dashes and middle dots.
"""

import io
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from xml.sax.saxutils import escape

from .dates import fmt_amount, fmt_date, fmt_datetime

# No settings/business-profile feature exists to make this configurable —
# hardcoded until one does, exactly as in Version 1.
BUSINESS_NAME = "Duka POS"

_PAYMENT_LABELS = {"cash": "Cash", "mpesa": "M-Pesa", "card": "Card", "credit": "Credit"}
_MARGIN = 2 * cm


# --- CSV ------------------------------------------------------------------

def _csv_field(value) -> str:
    text = "" if value is None else str(value)
    if any(ch in text for ch in '",\r\n'):
        return '"' + text.replace('"', '""') + '"'
    return text


def build_csv(headers: list, rows) -> str:
    lines = [",".join(_csv_field(h) for h in headers)]
    lines.extend(",".join(_csv_field(c) for c in row) for row in rows)
    return "\n".join(lines) + "\n"


def csv_bytes(text: str) -> bytes:
    """UTF-8 with a leading BOM — Excel on Windows guesses the encoding from
    the first bytes and mangles anything non-ASCII without it."""
    return ("﻿" + text).encode("utf-8")


def stamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def range_stamp(start: datetime, end: datetime) -> str:
    return f"{start:%Y%m%d}-{end:%Y%m%d}"


def subtitle_for_range(start: datetime, end: datetime) -> str:
    # Plain hyphen: the PDF's default font has no glyph for an en dash.
    return f"{fmt_date(start)} - {fmt_date(end)}"


# --- PDF building blocks -----------------------------------------------------

def _safe(text) -> str:
    return str("" if text is None else text).encode("cp1252", "replace").decode("cp1252")


def _p(text, **style) -> Paragraph:
    base = dict(fontName="Helvetica", fontSize=10, leading=13)
    base.update(style)
    return Paragraph(escape(_safe(text)), ParagraphStyle("x", **base))


def _document(buffer, **kwargs) -> SimpleDocTemplate:
    return SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=_MARGIN,
        rightMargin=_MARGIN,
        topMargin=_MARGIN,
        bottomMargin=_MARGIN,
        **kwargs,
    )


def _grid(headers: list, rows: list, *, right_from: int = 1) -> Table:
    data = [[_safe(h) for h in headers]] + [[_safe(c) for c in row] for row in rows]
    table = Table(data, repeatRows=1)
    style = [
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("LINEBELOW", (0, 0), (-1, 0), 1, colors.HexColor("#bdbdbd")),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]
    if right_from < len(headers):
        style.append(("ALIGN", (right_from, 0), (-1, -1), "RIGHT"))
    table.setStyle(TableStyle(style))
    return table


def _title_block(title: str, subtitle: str) -> list:
    return [
        _p(title, fontName="Helvetica-Bold", fontSize=18, leading=22),
        Spacer(1, 4),
        _p(subtitle, fontSize=11, leading=14, textColor=colors.HexColor("#616161")),
        Spacer(1, 16),
    ]


def _totals_line(cells: list) -> list:
    row = Table([[_p(c, fontName="Helvetica-Bold", alignment=2) for c in cells]], hAlign="RIGHT")
    return [HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#bdbdbd"), spaceBefore=6, spaceAfter=6), row]


def table_pdf(title: str, subtitle: str, headers: list, rows: list, totals_row: list | None = None) -> bytes:
    buffer = io.BytesIO()
    story = _title_block(title, subtitle) + [_grid(headers, rows)]
    if totals_row:
        story += _totals_line(totals_row)
    _document(buffer, title=_safe(title)).build(story)
    return buffer.getvalue()


def statement_pdf(title: str, subtitle: str, lines: list[tuple[str, str, bool]]) -> bytes:
    """`lines` are (label, value, emphasize)."""
    buffer = io.BytesIO()
    rows = []
    styles = []
    for index, (label, value, emphasize) in enumerate(lines):
        font = "Helvetica-Bold" if emphasize else "Helvetica"
        rows.append([_safe(label), _safe(value)])
        styles.append(("FONTNAME", (0, index), (-1, index), font))
    table = Table(rows, colWidths=[None, 6 * cm])
    table.setStyle(
        TableStyle(
            [("ALIGN", (1, 0), (1, -1), "RIGHT"), ("FONTSIZE", (0, 0), (-1, -1), 10)]
            + styles
            + [("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
        )
    )
    _document(buffer, title=_safe(title)).build(_title_block(title, subtitle) + [table])
    return buffer.getvalue()


# --- receipt ----------------------------------------------------------------

def receipt_pdf(sale: dict, items: list[dict], products_by_id: dict, cashier: dict | None, customer: dict | None) -> bytes:
    buffer = io.BytesIO()
    balance_due = sale["total"] - sale["amount_paid"]

    def totals_row(label, value, bold=False):
        font = "Helvetica-Bold" if bold else "Helvetica"
        row = Table([[_safe(label), fmt_amount(value)]], colWidths=[None, 5 * cm])
        row.setStyle(
            TableStyle(
                [
                    ("FONTNAME", (0, 0), (-1, -1), font),
                    ("FONTSIZE", (0, 0), (-1, -1), 10),
                    ("ALIGN", (1, 0), (1, 0), "RIGHT"),
                    ("TOPPADDING", (0, 0), (-1, -1), 2),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ]
            )
        )
        return row

    story = [
        _p(BUSINESS_NAME, fontName="Helvetica-Bold", fontSize=20, leading=24, alignment=1),
        Spacer(1, 16),
        _p(f"Receipt: {sale['invoice_number']}"),
        _p(f"Date: {fmt_datetime(sale['created_at'])}"),
        _p(f"Cashier: {cashier['full_name'] if cashier else 'Unknown'}"),
        _p(f"Customer: {customer['name'] if customer else 'Walk-in customer'}"),
        Spacer(1, 16),
        _grid(
            ["Item", "Qty", "Price", "Total"],
            [
                [
                    (products_by_id.get(i["product_id"]) or {}).get("name", "Unknown product"),
                    fmt_amount(i["quantity"]),
                    fmt_amount(i["unit_price"]),
                    fmt_amount(i["total"]),
                ]
                for i in items
            ],
        ),
        HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#bdbdbd"), spaceBefore=8, spaceAfter=8),
        totals_row("Subtotal", sale["subtotal"]),
    ]
    if sale["discount"] > 0:
        story.append(totals_row("Discount", -sale["discount"]))
    if sale["tax"] > 0:
        story.append(totals_row("Tax", sale["tax"]))
    story.append(totals_row("Total", sale["total"], bold=True))
    story += [
        Spacer(1, 12),
        _p(f"Payment method: {_PAYMENT_LABELS.get(sale['payment_method'], sale['payment_method'])}"),
        totals_row("Amount paid", sale["amount_paid"]),
    ]
    if balance_due > 0:
        story.append(totals_row("Balance due", balance_due, bold=True))
    story += [Spacer(1, 24), _p("Thank you for your business!", fontSize=10, alignment=1)]

    _document(buffer, title=_safe(f"{sale['invoice_number']}")).build(story)
    return buffer.getvalue()


# --- sales history ------------------------------------------------------------

def _customer_name(sale: dict, customer_by_id: dict) -> str:
    if sale["customer_id"] is None:
        return "Walk-in"
    return (customer_by_id.get(sale["customer_id"]) or {}).get("name", "-")


def _status_label(sale: dict) -> str:
    if sale["status"] == "void":
        return "Void"
    return "On account" if sale["total"] - sale["amount_paid"] > 0 else "Paid"


def sales_history_csv(sales: list[dict], customer_by_id: dict) -> bytes:
    return csv_bytes(
        build_csv(
            ["Receipt", "Date", "Customer", "Total", "Paid", "Status"],
            [
                [
                    s["invoice_number"],
                    fmt_datetime(s["created_at"]),
                    _customer_name(s, customer_by_id),
                    f"{s['total']:.2f}",
                    f"{s['amount_paid']:.2f}",
                    _status_label(s),
                ]
                for s in sales
            ],
        )
    )


def sales_history_pdf(sales: list[dict], customer_by_id: dict) -> bytes:
    total_revenue = sum(s["total"] for s in sales if s["status"] != "void")
    return table_pdf(
        "Sales history",
        f"{len(sales)} sale(s)",
        ["Receipt", "Date", "Customer", "Total", "Paid", "Status"],
        [
            [
                s["invoice_number"],
                fmt_datetime(s["created_at"]),
                _customer_name(s, customer_by_id),
                fmt_amount(s["total"]),
                fmt_amount(s["amount_paid"]),
                _status_label(s),
            ]
            for s in sales
        ],
        ["Total revenue (excl. void)", fmt_amount(total_revenue)],
    )


# --- reports ------------------------------------------------------------------

def sales_report_csv(report: dict, start: datetime, end: datetime) -> bytes:
    lines = [
        build_csv(["Sales report"], []),
        build_csv(["Period", subtitle_for_range(start, end)], []),
        build_csv(
            ["Total revenue", "Sales", "Average sale"],
            [[f"{report['totalRevenue']:.2f}", report["saleCount"], f"{report['averageSaleValue']:.2f}"]],
        ),
        "\n",
        build_csv(
            ["Product", "Quantity sold", "Revenue"],
            [[r["productName"], f"{r['quantitySold']:.2f}", f"{r['revenue']:.2f}"] for r in report["productBreakdown"]],
        ),
    ]
    return csv_bytes("".join(lines))


def sales_report_pdf(report: dict, start: datetime, end: datetime) -> bytes:
    return table_pdf(
        "Sales report",
        # Plain " | " separators: the PDF's default font has no glyph for a
        # middle dot.
        f"{subtitle_for_range(start, end)}  |  {report['saleCount']} sale(s)  |  "
        f"Total {fmt_amount(report['totalRevenue'])}  |  Average {fmt_amount(report['averageSaleValue'])}",
        ["Product", "Quantity sold", "Revenue"],
        [[r["productName"], fmt_amount(r["quantitySold"]), fmt_amount(r["revenue"])] for r in report["productBreakdown"]],
        ["Total revenue", fmt_amount(report["totalRevenue"])],
    )


def _pnl_lines(report: dict) -> list[tuple[str, float]]:
    return [
        ("Subtotal", report["subtotal"]),
        ("Discount", -report["discount"]),
        ("Net revenue", report["netRevenue"]),
        ("Cost of goods sold", -report["cogs"]),
        ("Gross profit", report["grossProfit"]),
        ("Expenses", -report["expenses"]),
        ("Net profit", report["netProfit"]),
    ]


def pnl_csv(report: dict, start: datetime, end: datetime) -> bytes:
    return csv_bytes(
        build_csv(["Profit & loss report"], [])
        + build_csv(["Period", subtitle_for_range(start, end)], [])
        + "\n"
        + build_csv(["Line", "Amount"], [[label, f"{value:.2f}"] for label, value in _pnl_lines(report)])
    )


def pnl_pdf(report: dict, start: datetime, end: datetime) -> bytes:
    emphasized = {"Net revenue", "Gross profit", "Net profit"}
    return statement_pdf(
        "Profit & loss report",
        subtitle_for_range(start, end),
        [(label, fmt_amount(value), label in emphasized) for label, value in _pnl_lines(report)],
    )


def _movement_rows(report: dict) -> list[tuple[str, float]]:
    by_type = {m["type"]: m["totalQuantity"] for m in report["movementSummary"]}
    return [(t, by_type.get(t, 0.0)) for t in ("PURCHASE", "SALE", "RETURN", "ADJUSTMENT")]


def inventory_csv(report: dict, start: datetime, end: datetime) -> bytes:
    return csv_bytes(
        build_csv(["Inventory report"], [])
        + build_csv(["Period", subtitle_for_range(start, end)], [])
        + "\n"
        + build_csv(
            ["Product", "Stock", "Avg cost", "Stock value"],
            [
                [l["name"], f"{l['stock']:.2f}", f"{l['averageCost']:.2f}", f"{l['stockValue']:.2f}"]
                for l in report["stockLevels"]
            ],
        )
        + "\n"
        + build_csv(["Movement type", "Net quantity"], [[t, f"{q:.2f}"] for t, q in _movement_rows(report)]).rstrip("\n")
        + "\n"
    )


def inventory_pdf(report: dict, start: datetime, end: datetime) -> bytes:
    buffer = io.BytesIO()
    total_value = sum(l["stockValue"] for l in report["stockLevels"])
    bold = dict(fontName="Helvetica-Bold")
    story = _title_block("Inventory report", subtitle_for_range(start, end)) + [
        _p("Stock levels", **bold),
        Spacer(1, 6),
        _grid(
            ["Product", "Stock", "Avg cost", "Stock value"],
            [
                [l["name"], fmt_amount(l["stock"]), fmt_amount(l["averageCost"]), fmt_amount(l["stockValue"])]
                for l in report["stockLevels"]
            ],
        ),
        *_totals_line(["Total stock value", fmt_amount(total_value)]),
        Spacer(1, 20),
        _p("Stock movement", **bold),
        Spacer(1, 6),
        _grid(["Movement type", "Net quantity"], [[t, fmt_amount(q)] for t, q in _movement_rows(report)]),
    ]
    _document(buffer, title="Inventory report").build(story)
    return buffer.getvalue()
