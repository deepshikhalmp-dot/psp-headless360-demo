"""Coworker runs for the Evidence Guide. Each run starts a New chat, sends prompts in order and saves a
screenshot after each answer. Usage: python coworker.py <run-id>"""
import sys
import time
from ui import Session

RUNS = {
    "C1": [("C1-worklist-card", "Show today's Zenthera patient support exceptions.")],
    "C2": [("C2-three-agents-plan", "Show today's PSP exceptions, consult the delayed shipment policy and prepare a resolution plan.")],
    "C3": [("C3-ai-handoff-enr0007", "Prepare a care team handoff for enrollment ENR-0007. Do not create, update or share anything.")],
    "C4": [("C4-duplicate-guard-00001124", "Using the PSP Care Resolution Agent, create a Refill Support case for ENR-0007: the coordinator wants to confirm the next refill date with the pharmacy.")],
    "C6": [("C6-resolution-plan", "Using the PSP Care Resolution Agent, prepare a resolution plan for today's PSP program exceptions.")],
    "C7": [("C7-exceptions-enr0063", "Show today's Zenthera PSP program exceptions for enrollment ENR-0063.")],
    "C5": [("C5-program-question", "What is the Zenthera PSP process for delayed shipments?")],
    "W4": [("W4-01-proposal", "Using the PSP Care Resolution Agent, prepare a Shipment Delay case for ENR-0059, shipment DSP-0073, with the subject \"Follow up delayed shipment DSP-0073 with the pharmacy\". Show me the proposal first."),
           ("W4-02-after-yes", "yes")],
}


def input_box(page):
    for locator in (page.get_by_role("textbox", name="Try", exact=False), page.locator("[aria-label^='Try']"),
                    page.locator("textarea:visible"), page.locator("[contenteditable=true]:visible")):
        if locator.count() > 0:
            return locator.last
    raise RuntimeError("Coworker input not found")


def wait_answer(s, max_seconds=420, quiet=int(__import__("os").environ.get("QUIET", "25"))):
    last, same = "", 0
    for _ in range(max_seconds // 5):
        time.sleep(5)
        text = s.page.inner_text("body")
        busy = any(w in text[-3000:] for w in ("Thinking", "Working on it", "Generating"))
        same = same + 5 if text == last and not busy else 0
        last = text
        if same >= quiet:
            return text
    return last


run = sys.argv[1]
with Session(height=2200) as s:
    page = s.page
    s.go("/lightning/coworker", 10)
    try:
        page.get_by_text("New chat", exact=True).first.click(timeout=8000)
        time.sleep(5)
        print("STEP new chat")
    except Exception as error:
        print("STEP new chat skipped", str(error)[:80])
    for name, prompt in RUNS[run]:
        box = input_box(page)
        box.click()
        box.fill(prompt)
        time.sleep(1)
        page.keyboard.press("Enter")
        text = wait_answer(s)
        s.shot(name)
        tail = text[-2500:].replace("\n", " | ")
        print("ANSWER", name, tail)
        if name == "W4-02-after-yes":
            confirm = page.get_by_role("button", name="Confirm")
            if confirm.count() > 0:
                s.shot("W4-03-confirmation-card")
                confirm.last.click()
                text = wait_answer(s)
                s.shot("W4-04-case-created")
                print("ANSWER W4-04", text[-2000:].replace("\n", " | "))
            else:
                print("NO_CONFIRM_BUTTON")
