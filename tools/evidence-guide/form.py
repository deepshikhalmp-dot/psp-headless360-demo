"""Form helpers for Lightning record forms (Playwright locators pierce shadow DOM)."""
import time


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


def wait_record(page, marker, seconds=60):
    """Lightning navigates with pushState, so poll the URL instead of waiting for a load event."""
    for _ in range(seconds):
        if marker in page.url and "/view" in page.url:
            time.sleep(8)
            return page.url
        time.sleep(1)
    raise RuntimeError("Record page did not open; still on " + page.url)
