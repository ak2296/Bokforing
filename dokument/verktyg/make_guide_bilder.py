"""Cuts the phone guide PDF into picture slices for the app's guide reader, so the
phone never has to render a PDF (slow, heavy on RAM, and a tall page can be
taller than an old phone's largest texture).

    py dokument/verktyg/make_guide_bilder.py

Writes assets/guide/index.json and assets/guide/pNN_K.webp (900 px wide, at most
about 1200 px tall, cut in a blank row when there is one so no seam shows).
Needs pymupdf and pillow (pip install pymupdf pillow). make_docs.py runs it.
"""
import json
import pathlib
import shutil
import sys

import pymupdf
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
PDF = ROOT / "dokument/anvandarguide/anvandarguide-telefon.pdf"
OUT = ROOT / "assets/guide"
WIDTH = 900
SLICE = 1200
SEARCH = 350  # how far above the target to look for a blank row


def blank_row(img: Image.Image, y: int) -> bool:
    return all(lo == hi for lo, hi in img.crop((0, y, img.width, y + 1)).getextrema())


def cut_points(img: Image.Image) -> list[int]:
    cuts, y = [0], 0
    while img.height - y > SLICE + SEARCH // 2:
        target = y + SLICE
        cut = next((c for c in range(target, target - SEARCH, -1) if blank_row(img, c)), target)
        cuts.append(cut)
        y = cut
    cuts.append(img.height)
    return cuts


def main() -> int:
    if not PDF.exists():
        print(f"{PDF} saknas")
        return 1
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    doc = pymupdf.open(PDF)
    pages = []
    total = 0
    for n, page in enumerate(doc, start=1):
        scale = WIDTH / page.rect.width
        pm = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale), alpha=False)
        img = Image.frombytes("RGB", (pm.width, pm.height), pm.samples)
        cuts = cut_points(img)
        tiles = []
        for k, (a, b) in enumerate(zip(cuts, cuts[1:])):
            name = f"p{n:02d}_{k}.webp"
            img.crop((0, a, img.width, b)).save(OUT / name, "WEBP", quality=88, method=6)
            tiles.append({"f": name, "h": b - a})
            total += (OUT / name).stat().st_size
        pages.append(tiles)
    (OUT / "index.json").write_text(json.dumps({"width": WIDTH, "pages": pages}), encoding="utf-8")
    print(f"assets/guide: {len(pages)} sidor, {sum(len(p) for p in pages)} bilder, {total / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
