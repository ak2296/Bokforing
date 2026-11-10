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
.side:last-child {{ page-break-after: auto; }}
.half {{ position: absolute; left: 0; width: 210mm; height: 148.5mm; display: flex; }}
.slot {{ width: 105mm; height: 148.5mm; overflow: hidden; position: relative; }}
.slot > .page {{ transform: scale({SCALE:.5f}); transform-origin: 0 0; page-break-after: auto; }}
.mark-v {{ position: absolute; left: 105mm; width: 0; height: 3mm; border-left: 0.2mm solid #b9b9b9; }}
.mark-h {{ position: absolute; top: 148.5mm; height: 0; width: 4mm; border-top: 0.2mm solid #b9b9b9; }}
.backcover .mark {{ position: absolute; left: 0; right: 0; bottom: 16mm; display: flex; flex-direction: column; align-items: center; gap: 2mm; }}
.backcover .mark img {{ width: 11mm; height: 11mm; border-radius: 2.6mm; }}
.backcover .mark span {{ font-size: 9pt; font-weight: 500; color: #0B6B4E; letter-spacing: 0.3pt; }}
.notes .line {{ height: 7.4mm; border-bottom: 0.25mm solid #DCE3DB; }}
</style>
"""


def half(top: bool, left: str, right: str) -> str:
    y = "0" if top else "148.5mm"
    return f'<div class="half" style="top:{y}"><div class="slot">{left}</div><div class="slot">{right}</div></div>'


def side(halves: list[str]) -> str:
    # Fold marks in the middle of each half, cut marks across the middle.
    marks = ('<div class="mark-v" style="top:0"></div><div class="mark-v" style="top:145.5mm"></div>'
             '<div class="mark-v" style="top:148.5mm"></div><div class="mark-v" style="bottom:0"></div>'
             '<div class="mark-h" style="left:0"></div><div class="mark-h" style="right:0"></div>')
    return f'<div class="side">{"".join(halves)}{marks}</div>'


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
        sides.append(side([half(i == 0, *s[0]) for i, s in enumerate(pair)]))
        sides.append(side([half(i == 0, *s[1]) for i, s in enumerate(pair)]))
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
