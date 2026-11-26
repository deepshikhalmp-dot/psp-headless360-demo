"""Crop the empty area below the last chat message in tall Coworker screenshots (uses Chrome canvas, no extra packages)."""
import base64, glob, os, sys
from playwright.sync_api import sync_playwright
SCREENS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "docs", "evidence-guide", "screens"))
JS = """async (src) => {
  const img = new Image(); img.src = src; await img.decode();
  const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
  const g = c.getContext('2d'); g.drawImage(img, 0, 0);
  const top = 120, bottom = img.height - 160, x0 = 540, x1 = 1360;
  const d = g.getImageData(x0, 0, x1 - x0, img.height).data, w = x1 - x0;
  let last = top;
  for (let y = top; y < bottom; y++) {
    for (let x = 0; x < w; x += 2) {
      const i = (y * w + x) * 4;
      if (d[i] < 225 || d[i+1] < 225 || d[i+2] < 225) { last = y; break; }
    }
  }
  const h = Math.min(img.height, last + 60);
  const o = document.createElement('canvas'); o.width = img.width; o.height = h;
  o.getContext('2d').drawImage(img, 0, 0);
  return [h, o.toDataURL('image/png')];
}"""
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    page = b.new_page()
    for path in sorted(glob.glob(os.path.join(SCREENS, "C*.png")) + glob.glob(os.path.join(SCREENS, "W4-0[1-4]*.png"))):
        src = "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()
        h, url = page.evaluate(JS, src)
        open(path, "wb").write(base64.b64decode(url.split(",", 1)[1]))
        print(os.path.basename(path), h)
    b.close()
