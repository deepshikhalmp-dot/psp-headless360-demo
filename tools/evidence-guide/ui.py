"""Shared helpers for the PSP Evidence Guide UI runs (Playwright, installed Chrome, headless).

Login uses a frontdoor URL from env SF_FRONTDOOR (never written to disk). A persistent profile in
.profile-<name> keeps the session between runs. Every step saves a screenshot.
"""
import os
import time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
SCREENS = os.environ.get("SHOTS_DIR") or os.path.abspath(os.path.join(HERE, "..", "..", "docs", "evidence-guide", "screens"))


class Session:
    def __init__(self, profile="presenter", height=1000):
        self.profile_dir = os.environ.get("PROFILE_DIR") or os.path.join(HERE, ".profile-" + profile)
        self.height = height
        self.base = None

    def __enter__(self):
        self.pw = sync_playwright().start()
        self.ctx = self.pw.chromium.launch_persistent_context(
            self.profile_dir, channel="chrome", headless=True,
            viewport={"width": 1600, "height": self.height}, device_scale_factor=1)
        self.page = self.ctx.pages[0] if self.ctx.pages else self.ctx.new_page()
        frontdoor = os.environ["SF_FRONTDOOR"]
        self.base = frontdoor.split("/secur/")[0]
        self.page.goto(frontdoor, wait_until="domcontentloaded", timeout=90000)
        self.page.wait_for_url("**/lightning/**", timeout=90000)
        time.sleep(5)
        return self

    def __exit__(self, *args):
        self.ctx.close()
        self.pw.stop()

    def go(self, path, wait=8):
        self.page.goto(self.base + path, wait_until="domcontentloaded", timeout=90000)
        try:
            self.page.wait_for_load_state("networkidle", timeout=20000)
        except Exception:
            pass
        time.sleep(wait)

    def shot(self, name, full=False):
        os.makedirs(SCREENS, exist_ok=True)
        path = os.path.join(SCREENS, name + ".png")
        self.page.screenshot(path=path, full_page=full)
        print("SHOT", name)
        return path

    def text(self, limit=4000):
        return self.page.inner_text("body")[:limit]
