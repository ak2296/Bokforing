"""Makes the PDF files in dokument/ from their HTML sources with Microsoft
Edge (headless), which is already on Windows. Nothing is installed.

    python dokument/verktyg/make_docs.py

Run it after changing a design or the user guide, then commit both the HTML
and the PDF. The guide is also cut into picture slices in assets/guide/ so the app carries it
(a change there starts an app build).
"""
import os
import re
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
EDGE_PATHS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]
DOCS = [
    "dokument/anvandarguide/anvandarguide.html",
    "dokument/anvandarguide/anvandarguide-telefon.html",
    "dokument/anvandarguide/anvandarguide-A6-tryckfil.html",
    "dokument/kort/kort.html",
    "dokument/forpackning/forpackning.html",
    "dokument/forpackning/forpackning-tryckfil.html",
    "dokument/forpackning/forpackning-stans.html",
]


def main() -> int:
    edge = next((p for p in EDGE_PATHS if os.path.exists(p)), None)
    if edge is None:
        print("Microsoft Edge hittades inte.")
        return 1
    # The print booklet is made from the guide first.
    subprocess.run([sys.executable, "-I", str(ROOT / "dokument/verktyg/make_booklet.py")], check=True)
    subprocess.run([sys.executable, "-I", str(ROOT / "dokument/verktyg/make_telefon.py")], check=True)
    subprocess.run([sys.executable, "-I", str(ROOT / "dokument/verktyg/make_tryckfiler.py")], check=True)
    for rel in DOCS:
        src = ROOT / rel
        if not src.exists():
            continue
        out = src.with_suffix(".pdf")
        subprocess.run(
            [edge, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=5000",
             f"--print-to-pdf={out}", src.as_uri()],
            check=True, capture_output=True,
        )
        print(f"{rel} -> {out.name}")
    # The titles of the chapters, for the contents list in the app's guide reader.
    html = (ROOT / "dokument/anvandarguide/anvandarguide.html").read_text(encoding="utf-8")
    titles = re.findall(r'<li><span>\d+</span><span><a href="#s\d+">(.*?)</a></span>', html)
    (ROOT / "assets/anvandarguide_innehall.txt").write_text("\n".join(titles) + "\n", encoding="utf-8")
    print(f"assets/anvandarguide_innehall.txt: {len(titles)} kapitel")
    # The app carries the phone version of the guide as picture slices (no PDF is
    # rendered on the phone), shown in Inställningar → Användarguide.
    subprocess.run([sys.executable, "-I", str(ROOT / "dokument/verktyg/make_guide_bilder.py")], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
