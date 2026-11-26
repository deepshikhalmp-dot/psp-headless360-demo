"""Copies the run screenshots into docs/perf-guide/screens and crops the Coworker ones to the chat area.
Uses Chrome canvas through Playwright (no extra packages). Usage: python prep_screens.py <raw-shots-dir>"""
import base64, os, shutil, sys
from playwright.sync_api import sync_playwright

RAW = sys.argv[1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "perf-guide", "screens")
os.makedirs(OUT, exist_ok=True)

CROP_JS = """async ([src, x0, y0, x1, scanBottom]) => {
  const img = new Image(); img.src = src; await img.decode();
  const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
  const g = c.getContext('2d'); g.drawImage(img, 0, 0);
  const w = x1 - x0, d = g.getImageData(x0, 0, w, img.height).data;
  let last = y0 + 100;
  for (let y = y0 + 20; y < Math.min(scanBottom, img.height); y++) {
    for (let x = 20; x < w - 20; x += 3) { const i = (y * w + x) * 4; if (d[i] < 235 || d[i+1] < 235 || d[i+2] < 235) { last = y; break; } }
  }
  const h = Math.min(last + 40, img.height) - y0;
  const o = document.createElement('canvas'); o.width = w; o.height = h;
  o.getContext('2d').drawImage(img, x0, y0, w, h, 0, 0, w, h);
  return o.toDataURL('image/png').split(',')[1];
}"""


def copy(src, dst):
    shutil.copyfile(os.path.join(RAW, src), os.path.join(OUT, dst))


with sync_playwright() as pw:
    browser = pw.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page()

    def coworker(src, dst):
        data = base64.b64encode(open(os.path.join(RAW, src), "rb").read()).decode()
        out = page.evaluate(CROP_JS, ["data:image/png;base64," + data, 300, 90, 1600, 1850])
        open(os.path.join(OUT, dst), "wb").write(base64.b64decode(out))

    copy("x-audit.png", "S1-monitoring-setup.png")
    copy("b1-canvas.png", "S2-builder-canvas.png")
    copy("b2-progex.png", "S2-program-exceptions-before-reasoning.png")
    for t in ("T01", "T02", "T03", "T04", "T05", "T06", "T07"):
        copy(f"P-{t}.png", f"S4-preview-{t}.png")
    for t in ("T01", "T02", "T04", "T05", "T06", "T07"):
        coworker(f"C-{t}.png", f"S5-coworker-{t}.png")
    coworker("C-T03-run2.png", "S5-coworker-T03-run2.png")
    for q in ("QA", "QB", "QC", "QD"):
        copy(f"S5-{q}.png", f"S5-query-editor-{q}.png")
    for name in ("S7-v7-1-details", "S7-v7-2-conditions", "S7-v7-3-data", "S7-v7-result", "S7-v6-result", "S9-digital-wallet", "S9-agent-analytics"):
        copy(name + ".png", name + ".png")
    browser.close()
print(sorted(os.listdir(OUT)))
