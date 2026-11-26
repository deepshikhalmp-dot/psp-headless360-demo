import time
from ui import Session
with Session(profile="setup") as s:
    page = s.page
    s.go("/lightning/setup/SetupOneHome/home", 8)
    box = page.get_by_placeholder("Quick Find").first
    box.click(); box.press_sequentially("MCP Servers", delay=120); time.sleep(5)
    page.get_by_text("MCP Servers", exact=True).last.click()
    time.sleep(15)
    frame = page
    search = page.get_by_placeholder("Search").last
    search.click(); search.press_sequentially("PSP", delay=120); search.press("Enter"); time.sleep(8)
    s.shot("T08-setup-mcp-servers")
    for name in ["PSP Handoff MCP"]:
        link = page.get_by_text(name, exact=True)
        print(name, link.count())
