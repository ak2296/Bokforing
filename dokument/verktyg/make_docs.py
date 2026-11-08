"""Makes the PDF files in dokument/ from their HTML sources with Microsoft
Edge (headless), which is already on Windows. Nothing is installed.

    python dokument/verktyg/make_docs.py

Run it after changing a design or the user guide, then commit both the HTML
and the PDF.
"""
import os
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
    "dokument/kort/kort.html",
    "dokument/forpackning/forpackning.html",
]


def main() -> int:
    edge = next((p for p in EDGE_PATHS if os.path.exists(p)), None)
    if edge is None:
        print("Microsoft Edge hittades inte.")
        return 1
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
