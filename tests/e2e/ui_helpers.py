"""Browser-test helpers (kept out of conftest.py so it can't clash with tests/conftest.py)."""

import os
from pathlib import Path

HEADERS = {"X-Requested-With": "duka"}


class Ui:
    """A browser plus a few helpers."""

    def __init__(self, browser, base, width=1280, height=800):
        self.base = base
        self.ctx = browser.new_context(viewport={"width": width, "height": height})
        self.page = self.ctx.new_page()
        self.problems = []
        self.page.on("pageerror", lambda e: self.problems.append(f"pageerror: {e}\n{e.stack}"))
        # Chrome logs every 4xx the app deliberately provokes (a wrong password,
        # a refused sale) as a console error; script errors are what matter here.
        self.page.on(
            "console",
            lambda m: self.problems.append(f"console.{m.type}: {m.text}")
            if m.type == "error" and "Failed to load resource" not in m.text
            else None,
        )
        self.shots = os.environ.get("DUKA_SHOTS")
        self._n = 0

    # --- api (shares the browser's cookies) ---
    def api(self, method, path, data=None):
        r = self.ctx.request.fetch(self.base + path, method=method, data=data, headers=HEADERS)
        assert r.ok, (path, r.status, r.text())
        return r.json() if "json" in (r.headers.get("content-type") or "") else r

    def get(self, path):
        return self.api("GET", path)

    def post(self, path, data=None):
        return self.api("POST", path, data or {})

    # --- ui ---
    def goto(self, route):
        self.page.goto(f"{self.base}/#{route}")
        self.page.wait_for_timeout(300)

    def shot(self, name):
        if self.shots:
            Path(self.shots).mkdir(parents=True, exist_ok=True)
            self._n += 1
            self.page.screenshot(path=str(Path(self.shots) / f"{self._n:02d}_{name}.png"))

    def field(self, label):
        return self.page.locator(f".field:has(> label:text-is('{label}')) input, .field:has(> label:text-is('{label}')) textarea").first

    def select(self, label):
        return self.page.locator(f".field:has(> label:text-is('{label}')) select").first

    def choose(self, label, containing):
        """Pick the option whose text contains `containing`."""
        select = self.select(label)
        select.wait_for(state="attached")
        texts = select.locator("option").all_text_contents()
        index = next(i for i, t in enumerate(texts) if containing in t)
        select.select_option(index=index)

    def btn(self, text, exact=True):
        return self.page.get_by_role("button", name=text, exact=exact).first

    def sign_in(self, username, password):
        self.page.goto(self.base)
        self.page.wait_for_selector(".auth-card")
        self.page.locator(".auth-card input").nth(0).fill(username)
        self.page.locator(".auth-card input").nth(1).fill(password)
        self.page.locator(".auth-card .btn-filled").click()
        self.page.wait_for_selector(".appbar")

    def snack(self):
        return self.page.locator(".snackbar")

    def close(self):
        self.ctx.close()


def first_run(ui):
    ui.page.goto(ui.base)
    ui.page.wait_for_selector(".auth-card")
    inputs = ui.page.locator(".auth-card input")
    for i, value in enumerate(["Mary Manager", "mary", "secret1", "secret1"]):
        inputs.nth(i).fill(value)
    ui.page.get_by_role("button", name="Create account").click()
    ui.page.wait_for_selector(".appbar")


