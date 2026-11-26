"""W3 (approved 2026-11-26, option a): one Case on Kavya Evidence Demo from the Salesforce app, without
PSP category (the field is not on the Case layout). Refuses to run twice."""
import sys, time
from ui import Session
from form import fill, pick, wait_record

PATIENT = "001gL00002DBS8XQAX"
with Session() as s:
    page = s.page
    s.go("/lightning/r/Account/" + PATIENT + "/related/Cases/view", 8)
    if "Question about the program welcome kit" in s.text(20000):
        sys.exit("STOP: the case already exists; not creating another.")
    s.go("/lightning/o/Case/new?nooverride=1&defaultFieldValues=AccountId=" + PATIENT, 10)
    fill(page, "Subject", "Question about the program welcome kit")
    pick(page, "Case Origin", "Phone")
    time.sleep(1)
    s.shot("W3-01-new-case-form")
    page.get_by_role("button", name="Save", exact=True).click()
    time.sleep(12)
    s.shot("W3-02-after-save")
