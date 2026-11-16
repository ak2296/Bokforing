"""Counts the pages of the A6 booklet (the one that goes in the box) and works
out how deep the box has to be.

    python dokument/verktyg/tjocklek.py [papperstjocklek_mm]

The thickness of one leaf (one sheet of paper, two pages) depends on the paper
the printer uses; 0,12 mm is about 115 g/m2 silk. The result is a guide: ask the
printer for the real paper and stitching allowance before the box is ordered.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PDF = ROOT / "dokument/anvandarguide/anvandarguide-A6-tryckfil.pdf"
BOX_HTML = ROOT / "dokument/forpackning/forpackning.html"

CARD = 0.4      # the download card on top, mm
AIR = 2.0       # clearance so the lid closes without squeezing, mm
STITCH = 1.3    # stitching and the bulge of a folded booklet, factor


def pages() -> int:
    data = PDF.read_bytes()
    return len(re.findall(rb"/Type\s*/Page[^s]", data))


def main() -> None:
    caliper = float(sys.argv[1]) if len(sys.argv) > 1 else 0.12
    n = pages()
    leaves = n / 2  # two pages per leaf
    booklet = leaves * caliper * STITCH
    need = booklet + CARD + AIR
    depth = math.ceil(need)
    current = re.search(r"Innermått 109 × 152 × ([\d.,]+) mm", BOX_HTML.read_text(encoding="utf-8"))
    cur = float(current.group(1).replace(",", ".")) if current else 0
    print(f"Häftet: {n} sidor = {leaves:.0f} blad, papper {caliper} mm")
    print(f"Tjocklek häfte ca {booklet:.1f} mm + kort {CARD} + luft {AIR} = {need:.1f} mm -> lådans djup minst {depth} mm")
    print(f"Lådan är gjord för {cur:g} mm: " + ("räcker" if cur >= depth else f"ÄR FÖR GRUND, behöver {depth} mm"))
    spare = cur - CARD - AIR
    print(f"Plats för häftet upp till {spare:.1f} mm = ungefär {int(spare / (caliper * STITCH) * 2)} sidor med det här pappret")


if __name__ == "__main__":
    main()
