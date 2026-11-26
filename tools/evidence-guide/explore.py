import sys, json
from ui import Session
with Session() as s:
    s.go(sys.argv[1], 10)
    s.shot("_explore")
    data = s.page.evaluate("""() => Array.from(document.querySelectorAll('input,textarea,button[role=combobox],lightning-combobox button, [role=combobox]')).map(e => ({tag:e.tagName, name:e.getAttribute('name'), aria:e.getAttribute('aria-label'), id:e.id, ph:e.getAttribute('placeholder'), lbl:(e.labels&&e.labels[0]?e.labels[0].innerText:null)})).filter(x=>x.lbl||x.aria||x.name)""")
    for d in data[:80]: print(json.dumps(d))
