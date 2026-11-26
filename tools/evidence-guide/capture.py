"""Read-only screenshot capture for the PSP Evidence Guide.

Logs in with a Salesforce frontdoor URL (from `sf org open --url-only`, passed in env SF_FRONTDOOR,
never stored) and opens each page in the installed Google Chrome (headless). Nothing is clicked
except navigation, so nothing is created or changed.

Usage: SF_FRONTDOOR=... python capture.py shots.json out_dir
shots.json: [{"id": "S01", "url": "/lightning/...", "wait": 8, "full": false}]
"""
import json
import os
import sys
import time

from playwright.sync_api import sync_playwright


def main():
    shots = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    frontdoor = os.environ["SF_FRONTDOOR"]
    base = frontdoor.split("/secur/")[0]
    os.makedirs(out_dir, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(viewport={"width": 1600, "height": 1000}, device_scale_factor=1)
        page = context.new_page()
        page.goto(frontdoor, wait_until="domcontentloaded", timeout=90000)
        page.wait_for_url("**/lightning/**", timeout=90000)
        time.sleep(6)
        for shot in shots:
            if only and shot["id"] not in only:
                continue
            url = shot["url"] if shot["url"].startswith("http") else base + shot["url"]
            try:
                page.goto(url, wait_until="domcontentloaded", timeout=90000)
                try:
                    page.wait_for_load_state("networkidle", timeout=25000)
                except Exception:
                    pass
                time.sleep(shot.get("wait", 8))
                path = os.path.join(out_dir, shot["id"] + ".png")
                page.screenshot(path=path, full_page=shot.get("full", False))
                print("OK", shot["id"], page.title()[:80])
            except Exception as error:
                print("FAIL", shot["id"], str(error)[:200])
        browser.close()


if __name__ == "__main__":
    main()
