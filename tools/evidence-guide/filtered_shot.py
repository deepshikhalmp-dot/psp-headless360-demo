import time
from ui import Session
JOBS = [("T06-setup-prompt-builder", "Prompt Builder", "Search templates...", "PSP")]
with Session(profile="setup") as s:
    page = s.page
    for name, term, placeholder, filt in JOBS:
        s.go("/lightning/setup/SetupOneHome/home", 8)
        box = page.get_by_placeholder("Quick Find").first
        box.click(); box.press_sequentially(term, delay=120); time.sleep(5)
        page.get_by_text(term, exact=True).last.click(); time.sleep(14)
        search = page.get_by_placeholder(placeholder).last
        search.click(); search.press_sequentially(filt, delay=120); search.press("Enter"); time.sleep(8)
        s.shot(name)
