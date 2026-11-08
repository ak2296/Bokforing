"""Screenshots of single pages of a document in dokument/, for checking the
layout: python dokument/verktyg/preview_pages.py dokument/anvandarguide/anvandarguide.html 1 2 3 OUTDIR
The page size in mm is read from the @page rule."""
import pathlib
import re
import subprocess
import sys

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
src = pathlib.Path(sys.argv[1]).resolve()
pages, out = sys.argv[2:-1], pathlib.Path(sys.argv[-1]).resolve()
out.mkdir(parents=True, exist_ok=True)
m = re.search(r"@page\s*\{\s*size:\s*([\d.]+)mm\s+([\d.]+)mm", src.read_text(encoding="utf-8"))
w, h = (round(float(m[1]) * 96 / 25.4), round(float(m[2]) * 96 / 25.4)) if m else (559, 794)
for n in pages:
    target = out / f"{src.stem}-{n}.png"
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1.4",
                    f"--window-size={w},{h}", "--virtual-time-budget=4000", f"--screenshot={target}",
                    src.as_uri() + f"#s{n}"], check=True, capture_output=True)
    print(target)
