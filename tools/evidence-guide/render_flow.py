"""Renders usecase_flow.html to docs/evidence-guide/screens/U01-use-case-flow.png (local file, no login)."""
import os
from playwright.sync_api import sync_playwright
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "evidence-guide", "screens", "U01-use-case-flow.png"))
with sync_playwright() as pw:
    b = pw.chromium.launch(channel="chrome", headless=True)
    p = b.new_page(viewport={"width": 1500, "height": 1200}, device_scale_factor=2)
    p.goto("file://" + os.path.join(HERE, "usecase_flow.html"))
    p.locator("#flow").screenshot(path=OUT)
    b.close()
print("SHOT", OUT)
