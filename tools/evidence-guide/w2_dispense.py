"""W2 (approved 2026-11-25): one Delivered dispense on ENR-0063 (Kavya Evidence Demo). Refuses to run twice."""
import sys
from ui import Session
from form import fill, pick, lookup, wait_record

ENROLLMENT_ID = "a4tgL000000k0OPQAY"
with Session() as s:
    page = s.page
    s.go("/lightning/r/Program_Enrollment__c/" + ENROLLMENT_ID + "/related/Dispenses__r/view", 8)
    if "DSP-" in s.text(20000):
        sys.exit("STOP: ENR-0063 already has a dispense; not creating another.")
    s.go("/lightning/o/Dispense__c/new?nooverride=1&defaultFieldValues=Program_Enrollment__c=" + ENROLLMENT_ID, 10)
    fill(page, "Dispense Date", "11/25/2026")
    fill(page, "Days Supply", "30")
    fill(page, "Pharmacy", "Demo Specialty Pharmacy")
    pick(page, "Status", "Delivered")
    s.shot("W2-01-new-dispense-form")
    page.get_by_role("button", name="Save", exact=True).click()
    print("URL", wait_record(page, "/Dispense__c/a4s"))
    s.shot("W2-02-dispense-created")
    s.go("/lightning/r/Program_Enrollment__c/" + ENROLLMENT_ID + "/view", 10)
    s.shot("W2-03-enrollment-with-dispense", full=True)
