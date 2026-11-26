import sys
from ui import Session
with Session() as s:
    s.go(sys.argv[1], 10)
    t = s.page.inner_text("body")
    for w in sys.argv[2:]:
        print(w, "->", w in t)
    for w in ["Program Enrollment", "Dispense Date", "Days Supply", "Pharmacy", "Status"]:
        print("label", w, s.page.get_by_label(w).count(), "combobox", s.page.get_by_role("combobox", name=w).count())
