"""The shop assistant and the stock-health figures behind it."""

from .. import assistant, authz
from ..errors import ValidationError
from ..repos import insights
from . import actor, bp, body, db, ok


@bp.post("/assistant")
def ask_assistant():
    user = actor()
    question = str(body().get("question") or "")
    if len(question) > 500:
        raise ValidationError("Keep the question under 500 characters.")
    return ok(**assistant.polish(assistant.ask(db(), user, question), question))


@bp.get("/insights")
def stock_health():
    authz.require(actor(), authz.MANAGE_PRODUCTS)
    data = insights.product_insights(db())
    return ok(**data, summary=insights.summary(data))
