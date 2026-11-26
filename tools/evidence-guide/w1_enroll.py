"""W1 (approved 2026-11-25): create fictional patient Kavya Evidence Demo and her Zenthera enrollment in the
Salesforce app, with screenshots of each step. Refuses to run twice (checks for an existing patient)."""
import sys
import time

from ui import Session

PERSON_ACCOUNT_RT = "012gL000006oRqiQAE"


def fill(page, label, value):
    field = page.get_by_label(label, exact=True)
    if field.count() == 0:
        field = page.get_by_placeholder(label, exact=True)
    if field.count() == 0:
        field = page.get_by_label(label)
    field = field.first
    field.click()
    field.fill(value)


def pick(page, label, option):
    box = page.get_by_role("combobox", name=label, exact=True)
    if box.count() == 0:
        box = page.get_by_role("combobox", name=label)
    box.first.click()
    time.sleep(1)
    page.get_by_role("option", name=option, exact=True).first.click()
    time.sleep(1)


def lookup(page, label, search, option_text):
    box = page.get_by_role("combobox", name=label).first
    box.click()
    box.fill(search)
    time.sleep(3)
    page.get_by_role("option").filter(has_text=option_text).first.click()
    time.sleep(1)


with Session() as s:
    page = s.page
    step = sys.argv[1] if len(sys.argv) > 1 else "all"

    if step in ("all", "patient"):
        s.go("/lightning/o/Account/list?filterName=00BgL00000rPg2LUAS", 6)
        if "Kavya Evidence Demo" in s.text(20000):
            sys.exit("STOP: Kavya Evidence Demo already exists; not creating a second patient.")
        s.go("/lightning/o/Account/new?recordTypeId=" + PERSON_ACCOUNT_RT + "&nooverride=1", 8)
        fill(page, "First Name", "Kavya")
        fill(page, "Last Name", "Evidence Demo")
        fill(page, "Birthdate", "5/12/1990")
        fill(page, "Mobile", "+91 90000 22334")
        time.sleep(1)
        s.shot("W1-01-new-patient-form")
        page.get_by_role("button", name="Save", exact=True).click()
        page.wait_for_url(lambda u: "/Account/001" in u and "/view" in u, timeout=60000)
        time.sleep(8)
        s.shot("W1-02-patient-created")
        print("PATIENT_URL", page.url)

    if step == "patientshot":
        s.go("/lightning/r/Account/001gL00002DBS8XQAX/view", 10)
        s.shot("W1-02-patient-created")

    if step in ("all", "enrollment"):
        s.go("/lightning/o/Program_Enrollment__c/list", 6)
        s.go("/lightning/r/Account/001gL00002DBS8XQAX/related/Program_Enrollments__r/view", 8)
        if "ENR-" in s.text(20000):
            sys.exit("STOP: Kavya already has an enrollment; not creating a second one.")
        s.go("/lightning/o/Program_Enrollment__c/new?nooverride=1", 8)
        lookup(page, "Patient", "Kavya Evidence", "Kavya Evidence Demo")
        pick(page, "Program", "Zenthera Patient Support Program")
        pick(page, "Therapy", "Zenthera 100 mg")
        pick(page, "Status", "Enrolled")
        fill(page, "Enrollment Date", "11/25/2026")
        fill(page, "Prescriber Name", "Dr. Demo Rao")
        pick(page, "Insurance Type", "Commercial")
        page.get_by_label("Consent Given", exact=True).first.check()
        fill(page, "Consent Date", "11/25/2026")
        time.sleep(1)
        s.shot("W1-03-new-enrollment-form", full=True)
        page.get_by_role("button", name="Save", exact=True).click()
        page.wait_for_url(lambda u: "/Program_Enrollment__c/a4t" in u and "/view" in u, timeout=60000)
        time.sleep(8)
        s.shot("W1-04-enrollment-created")
        print("ENROLLMENT_URL", page.url)
