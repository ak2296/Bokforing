"""Makes the print file of the user guide for a printing company: an A6 booklet,
one page after the other in reading order (the printer imposes and staples it):

    front cover, blank, the guide's pages, blank, back cover

Each page is A6 (105 x 148.5 mm) plus 3 mm bleed on every side (111 x 154.5 mm);
only the front cover has colour out to the edge. The number of pages is a
multiple of four. The pages are cut by paginera_a6.py.

    python dokument/verktyg/make_booklet.py

Writes dokument/anvandarguide/anvandarguide-A6-tryckfil.html; make_docs.py turns
it into the PDF.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import paginera_a6  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
OUT = ROOT / "dokument/anvandarguide/anvandarguide-A6-tryckfil.html"
OLD = ["anvandarguide-tryck", "anvandarguide-tryck-omslag", "anvandarguide-tryck-inlaga"]

BLANK = '<section class="page"></section>'

BACK_COVER = """<section class="page backcover">
  <div class="mark"><img src="../bilder/app-ikon.png" alt=""><span>Quee</span></div>
</section>"""

STYLE = """
<style>
@page { size: 111mm 154.5mm; margin: 0; }
.bl { width: 111mm; height: 154.5mm; position: relative; overflow: hidden; page-break-after: always; }
.bl:last-child { page-break-after: auto; }
.bl .in { position: absolute; left: 3mm; top: 3mm; }
.bl .page { page-break-after: auto; }
.backcover .mark { position: absolute; left: 0; right: 0; bottom: 16mm; display: flex; flex-direction: column; align-items: center; gap: 2mm; }
.backcover .mark img { width: 11mm; height: 11mm; border-radius: 2.6mm; }
.backcover .mark span { font-family: Poppins, Inter, sans-serif; font-size: 10pt; font-weight: 600; color: #0B6B4E; letter-spacing: 0.3pt; }
</style>
"""


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    head = html[: html.index("<body>")]
    pages = paginera_a6.build()
    cover, inner = pages[0], pages[1:]
    book = [cover, BLANK, *inner, BLANK, BACK_COVER]
    while len(book) % 4:  # blanks before the back cover
        book.insert(-2, BLANK)

    h = head.replace("@page { size: 148mm 210mm; margin: 0; }", "").replace(
        "</head>", paginera_a6.STYLE.replace("@page { size: 105mm 148.5mm; margin: 0; }", "") + STYLE + "</head>", 1)
    h = re.sub(r"<title>.*?</title>", "<title>TRYCKFIL – Quee användarguide A6 med 3 mm utfall</title>", h, count=1)
    body = []
    for i, pg in enumerate(book):
        bg = "#0B6B4E" if i == 0 else "#fff"
        body.append(f'<div class="bl" style="background:{bg}"><div class="in">{pg}</div></div>')
    OUT.write_text(h + "<body>\n" + "\n".join(body) + "\n</body>\n</html>\n", encoding="utf-8")
    for name in OLD:  # the four-pages-per-sheet version is gone
        for ext in (".html", ".pdf"):
            f = OUT.parent / f"{name}{ext}"
            if f.exists():
                f.unlink()
    print(f"Häfte A6: {len(book)} sidor, en per PDF-sida, 3 mm utfall.")


if __name__ == "__main__":
    main()
