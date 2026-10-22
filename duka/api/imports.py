"""Bulk import from Excel / CSV sheets."""

from flask import Response, request

from .. import importer
from ..errors import ValidationError
from . import actor, bp, db, ok


@bp.get("/import/<kind>/template")
def import_template(kind):
    importer.require_permission(actor(), kind)
    return Response(
        importer.template(kind),
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="duka_{kind}_template.xlsx"'},
    )


@bp.post("/import/<kind>")
def import_sheet(kind):
    user = actor()
    importer.require_permission(user, kind)
    upload = request.files.get("file")
    if upload is None or not upload.filename:
        raise ValidationError("Choose an Excel (.xlsx) or CSV file.")
    commit = request.form.get("commit") == "1"
    return ok(**importer.run(db(), user, kind, upload.filename, upload.read(), commit=commit))
