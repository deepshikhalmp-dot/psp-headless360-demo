"""Read-only: open Setup pages through Quick Find and screenshot them."""
import time
from ui import Session
TARGETS = [("T08-setup-mcp-servers", "MCP Servers", "MCP Servers"),
           ("T11-setup-api-catalog", "API Catalog", "API Catalog"),
           ("T13-setup-coworker", "Coworker", "Get Started with Agentforce Coworker")]
with Session(profile="setup") as s:
    page = s.page
    for name, term, link in TARGETS:
        s.go("/lightning/setup/SetupOneHome/home", 8)
        box = page.get_by_placeholder("Quick Find").first
        box.click(); box.press_sequentially(term, delay=120); time.sleep(5)
        visible = [l for l in page.locator("a:visible").all() if (l.inner_text() or "").strip()]
        items = [l.inner_text().strip() for l in visible][:60]
        links = page.locator("[role=tree] a:visible, .tree a:visible, nav a:visible, a.highlight:visible").filter(has_text=link)
        if links.count() == 0:
            links = page.get_by_role("link", name=link, exact=True)
        print("RESULTS", term, items)
        if links.count() > 0:
            links.first.click(); time.sleep(12)
            s.shot(name)
            print("OPENED", name, page.url)
        else:
            s.shot(name + "-search")
