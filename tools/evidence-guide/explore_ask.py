import time, json
from ui import Session
with Session() as s:
    s.go("/lightning/page/home", 8)
    s.page.get_by_role("button", name="Ask").first.click()
    time.sleep(10)
    s.shot("_ask1")
    print("URL", s.page.url)
    print(json.dumps([ (e.get_attribute("aria-label"), e.get_attribute("placeholder")) for e in s.page.locator("textarea, [contenteditable=true], input").all()[:15]]))
