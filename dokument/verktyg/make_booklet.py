"""Makes the print version of the user guide: an A6 booklet, four pages per
side of an A4 sheet, cut across the middle, folded and stapled.

    python dokument/verktyg/make_booklet.py

Reads dokument/anvandarguide/anvandarguide.html (the normal guide, also in
the app) and writes anvandarguide-tryck.html beside it; make_docs.py turns it
into a PDF. One file holds everything, cover included:

    front cover, blank, the guide's pages, "Anteckningar", blank, back cover

Print it double-sided, flip on the LONG edge, at actual size (100 %). Each
A4 sheet holds two booklet sheets: cut it across the middle (the marks at the
edges show where). Stack the halves in print order, the top half of the
first A4 outermost, fold them together and staple twice in the fold.
Page numbers are the same as in the normal guide.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
OUT = ROOT / "dokument/anvandarguide/anvandarguide-tryck.html"
OLD = ["anvandarguide-tryck-omslag", "anvandarguide-tryck-inlaga"]

# The A5 guide page (148 x 210 mm) shrunk to A6 (105 x 148.5 mm).
SCALE = 148.5 / 210

# Printer registration. A duplex printer puts the back a little to one side of
# the front. Print the last A4 sheet (it has a measuring scale in its empty
# lower half), hold it to the light and read where the back's line crosses the
# front's scale: the number is this value in mm, plus when the back lies to the
# RIGHT as seen from the front, minus when to the left. The back sides are moved
# the other way to cancel it. 0 = no correction.
BACK_OFFSET_MM = 0.0

# Printers cannot print the outermost ~4-5 mm of the paper; the marks sit inside.
MARK_INSET = 6

BLANK = '<section class="page"></section>'

BACK_COVER = """<section class="page backcover">
  <div class="mark"><img src="../bilder/app-ikon.png" alt=""><span>Quee</span></div>
</section>"""


def notes_page(number: int) -> str:
    lines = "".join('<div class="line"></div>' for _ in range(22))
    return (f'<section class="page notes"><div class="kicker">Anteckningar</div><h1>Anteckningar</h1>{lines}'
            f'<div class="folio"><span>Anteckningar</span><span>{number}</span></div></section>')


STYLE = f"""
<style>
@page {{ size: 210mm 297mm; margin: 0; }}
.side {{ width: 210mm; height: 297mm; page-break-after: always; overflow: hidden; position: relative; }}
div.side:last-of-type {{ page-break-after: auto; }}
.side.back {{ transform: translateX({BACK_OFFSET_MM}mm); }}
.half {{ position: absolute; left: 0; width: 210mm; height: 148.5mm; display: flex; }}
.slot {{ width: 105mm; height: 148.5mm; overflow: hidden; position: relative; }}
.slot > .page {{ transform: scale({SCALE:.5f}); transform-origin: 0 0; page-break-after: auto; }}
.mark-v {{ position: absolute; left: 105mm; width: 0; height: 3mm; border-left: 0.25mm solid #777; }}
.mark-h {{ position: absolute; top: 148.5mm; height: 0; width: 4mm; border-top: 0.25mm solid #777; }}
.cal {{ position: absolute; left: 0; width: 210mm; font-size: 6pt; color: #555; }}
.cal .t {{ position: absolute; left: 0; right: 0; top: 0; text-align: center; }}
.cal .tick {{ position: absolute; width: 0; border-left: 0.2mm solid #000; }}
.cal .lab {{ position: absolute; width: 8mm; margin-left: -4mm; text-align: center; font-size: 5.5pt; }}
.backcover .mark {{ position: absolute; left: 0; right: 0; bottom: 16mm; display: flex; flex-direction: column; align-items: center; gap: 2mm; }}
.backcover .mark img {{ width: 11mm; height: 11mm; border-radius: 2.6mm; }}
.backcover .mark span {{ font-size: 9pt; font-weight: 500; color: #0B6B4E; letter-spacing: 0.3pt; }}
.notes .line {{ height: 7.4mm; border-bottom: 0.25mm solid #DCE3DB; }}
</style>
"""


def half(top: bool, left: str, right: str) -> str:
    y = "0" if top else "148.5mm"
    return f'<div class="half" style="top:{y}"><div class="slot">{left}</div><div class="slot">{right}</div></div>'


def side(halves: list[str], back: bool = False) -> str:
    # Fold marks in the middle of each half, cut marks across the middle; all
    # inside the part of the paper the printer can reach.
    i = MARK_INSET
    marks = (f'<div class="mark-v" style="top:{i}mm"></div><div class="mark-v" style="top:145.5mm"></div>'
             f'<div class="mark-v" style="top:148.5mm"></div><div class="mark-v" style="bottom:{i}mm"></div>'
             f'<div class="mark-h" style="left:{i}mm"></div><div class="mark-h" style="right:{i}mm"></div>')
    return f'<div class="side{" back" if back else ""}">{"".join(halves)}{marks}</div>'


def scale(front: bool) -> str:
    """Measuring scale for BACK_OFFSET_MM, in the empty lower half of the last
    A4: the front has a ruler centred on the fold line, the back one line."""
    if not front:
        return ('<div class="cal" style="top:170mm"><div class="t">Baksidan: en linje i mitten.</div>'
                '<div class="tick" style="left:105mm;top:6mm;height:10mm"></div></div>')
    parts = ['<div class="t">Passningsprov. Håll arket mot ljuset: baksidans linje ska ligga på 0. '
             'Läs av siffran där den hamnar (plus åt höger, minus åt vänster).</div>']
    for i in range(-12, 13):  # every 0.5 mm from -6 to +6
        h = 6 if i == 0 else 4 if i % 4 == 0 else 3 if i % 2 == 0 else 1.8
        parts.append(f'<div class="tick" style="left:{105 + i / 2}mm;top:8mm;height:{h}mm"></div>')
        if i % 4 == 0:  # a number every 2 mm, on two rows so they do not touch
            row = 15 if (i // 4) % 2 == 0 else 18.5
            parts.append(f'<div class="lab" style="left:{105 + i / 2}mm;top:{row}mm">{f"{i // 2:+d}" if i else "0"}</div>')
    return f'<div class="cal" style="top:170mm">{"".join(parts)}</div>'


def impose(book: list[str]) -> list[str]:
    """A4 sides in print order. Booklet sheet k (outermost first) carries
    pages last-2k | first+2k outside and first+2k+1 | last-2k-1 inside; two
    booklet sheets share an A4, top and bottom. Flipped on the long edge,
    left and right swap and top stays top, so the inside lines up."""
    n = len(book)
    sheets = [((book[n - 1 - 2 * k], book[2 * k]), (book[2 * k + 1], book[n - 2 - 2 * k])) for k in range(n // 4)]
    sides = []
    for j in range(0, len(sheets), 2):
        pair = sheets[j:j + 2]
        front = [half(i == 0, *s[0]) for i, s in enumerate(pair)]
        back = [half(i == 0, *s[1]) for i, s in enumerate(pair)]
        if len(pair) == 1:  # the empty lower half carries the measuring scale
            front.append(scale(True))
            back.append(scale(False))
        sides.append(side(front))
        sides.append(side(back, back=True))
    return sides


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    head = html[: html.index("<body>")]
    pages = re.findall(r'<section class="page[^"]*">.*?</section>', html, flags=re.S)
    if len(pages) < 2:
        raise SystemExit("Inga sidor hittades i guiden.")
    cover, inner = pages[0], pages[1:]
    # Front cover, its blank back, the guide (numbers kept: contents = 2),
    # notes to fill up, the back cover's blank front and the back cover.
    while (len(inner) + 4) % 4:
        inner.append(notes_page(len(inner) + 2))
    book = [cover, BLANK, *inner, BLANK, BACK_COVER]
    assert len(book) % 4 == 0

    h = head.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    h = re.sub(r"<title>.*?</title>", "<title>TRYCK – Quee användarguide A6 (dubbelsidigt, vänd längs långsidan)</title>", h, count=1)
    h = h.replace("</head>", STYLE + "</head>", 1)
    sides = impose(book)
    # file.html#s2 shows only sheet side 2 (used by preview_pages.py).
    preview = ("<script>var n = parseInt((location.hash || '').replace('#s', ''), 10);"
               "if (n) document.querySelectorAll('.side').forEach(function (s, i) { if (i !== n - 1) s.style.display = 'none'; });"
               "</script>")
    OUT.write_text(h + "<body>\n" + "\n".join(sides) + f"\n{preview}\n</body>\n</html>\n", encoding="utf-8")
    for name in OLD:
        for ext in (".html", ".pdf"):
            f = OUT.parent / f"{name}{ext}"
            if f.exists():
                f.unlink()
    print(f"Häfte A6: {len(book)} sidor på {len(sides) // 2} A4-ark, dubbelsidigt.")


if __name__ == "__main__":
    main()
