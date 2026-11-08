"""Makes the print version of the user guide: an A5 booklet printed on A4,
two pages per side, folded in the middle and stapled.

    python dokument/verktyg/make_booklet.py

Reads dokument/anvandarguide/anvandarguide.html (the normal guide, also in
the app) and writes two files beside it; make_docs.py turns them into PDFs:

- anvandarguide-tryck-omslag.html: the cover sheet, printed on ONE side:
  back cover (white, small logo and name) | front cover. Inside stays white.
- anvandarguide-tryck-inlaga.html: the inner pages, printed on BOTH sides
  (flip on the short edge). The first sheet carries the contents page and
  the last page; its other side the second and the second-to-last page, and
  so on. Lined "Anteckningar" pages fill up to a multiple of 4.

Fold the inner sheets, lay them in the cover sheet, fold, staple twice.
Page numbers are the same as in the normal guide.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
COVER_OUT = ROOT / "dokument/anvandarguide/anvandarguide-tryck-omslag.html"
INNER_OUT = ROOT / "dokument/anvandarguide/anvandarguide-tryck-inlaga.html"

BACK_COVER = """<section class="page backcover">
  <div class="mark"><img src="../bilder/app-ikon.png" alt=""><span>Quee</span></div>
</section>"""


def notes_page(number: int) -> str:
    lines = "".join('<div class="line"></div>' for _ in range(22))
    return (f'<section class="page notes"><div class="kicker">Anteckningar</div><h1>Anteckningar</h1>{lines}'
            f'<div class="folio"><span>Anteckningar</span><span>{number}</span></div></section>')


STYLE = """
<style>
@page { size: 297mm 210mm; margin: 0; }
.side { width: 297mm; height: 210mm; display: flex; page-break-after: always; overflow: hidden; position: relative; }
.side:last-child { page-break-after: auto; }
.slot { width: 148.5mm; height: 210mm; overflow: hidden; position: relative; }
.slot > .page { page-break-after: auto; }
.fold { position: absolute; left: 148.5mm; width: 0; height: 4mm; border-left: 0.2mm solid #b9b9b9; }
.backcover .mark { position: absolute; left: 0; right: 0; bottom: 16mm; display: flex; flex-direction: column; align-items: center; gap: 2mm; }
.backcover .mark img { width: 11mm; height: 11mm; border-radius: 2.6mm; }
.backcover .mark span { font-size: 9pt; font-weight: 500; color: #0B6B4E; letter-spacing: 0.3pt; }
.notes .line { height: 7.4mm; border-bottom: 0.25mm solid #DCE3DB; }
</style>
"""


def sheet(left: str, right: str) -> str:
    return (f'<div class="side"><div class="slot">{left}</div><div class="slot">{right}</div>'
            '<div class="fold" style="top:0"></div><div class="fold" style="bottom:0"></div></div>')


def write(path: pathlib.Path, head: str, title: str, sides: list[str]) -> None:
    h = head.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    h = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", h, count=1)
    h = h.replace("</head>", STYLE + "</head>", 1)
    path.write_text(h + "<body>\n" + "\n".join(sides) + "\n</body>\n</html>\n", encoding="utf-8")


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    head = html[: html.index("<body>")]
    pages = re.findall(r'<section class="page[^"]*">.*?</section>', html, flags=re.S)
    if len(pages) < 2:
        raise SystemExit("Inga sidor hittades i guiden.")
    cover, inner = pages[0], pages[1:]
    # The inner pages keep the guide's numbers: contents = 2, and so on.
    while len(inner) % 4:
        inner.append(notes_page(len(inner) + 2))
    n = len(inner)

    # Saddle stitch: sheet k outside = last-k | first+k, inside = first+k+1 | last-k-1.
    sides = []
    for k in range(n // 4):
        sides.append(sheet(inner[n - 1 - 2 * k], inner[2 * k]))
        sides.append(sheet(inner[2 * k + 1], inner[n - 2 - 2 * k]))

    write(COVER_OUT, head, "TRYCK – Quee användarguide, omslag (enkelsidigt)", [sheet(BACK_COVER, cover)])
    write(INNER_OUT, head, "TRYCK – Quee användarguide, inlaga (dubbelsidigt)", sides)
    old = ROOT / "dokument/anvandarguide/anvandarguide-tryck.html"
    for f in (old, old.with_suffix(".pdf")):
        if f.exists():
            f.unlink()
    print(f"Omslag: 1 ark enkelsidigt. Inlaga: {n} sidor på {n // 4} ark dubbelsidigt.")


if __name__ == "__main__":
    main()
