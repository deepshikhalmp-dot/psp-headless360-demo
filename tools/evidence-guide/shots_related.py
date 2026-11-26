"""Read-only: record pages and their Related tabs."""
import time
from ui import Session
SHOTS = [("W3-03-case-00001131-record", "/lightning/r/Case/500gL00001jWbgLQAS/view", None), ("W3-04-patient-kavya-related", "/lightning/r/Account/001gL00002DBS8XQAX/view", "Related")]
with Session() as s:
    for name, url, tab in SHOTS:
        s.go(url, 9)
        if tab:
            s.page.get_by_role("tab", name=tab, exact=True).first.click()
            time.sleep(6)
        s.shot(name)
