"""Makes the print version of the user guide: an A5 booklet printed on A4,
two pages per side, to fold in the middle and staple.

    python dokument/verktyg/make_booklet.py

Reads dokument/anvandarguide/anvandarguide.html (the normal guide, also in
the app) and writes anvandarguide-tryck.html beside it; make_docs.py turns
that into a PDF.

- The back of the cover is left white; every other page is printed on both
  sides.
- White pages are added at the end so the page count is a multiple of 4.
- Page numbers and the table of contents follow the printed booklet.
- Print: double-sided, flip on the SHORT edge, actual size (100 %).
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
OUT = ROOT / "dokument/anvandarguide/anvandarguide-tryck.html"

BLANK = '<section class="page blank"></section>'


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    head = html[: html.index("<body>")]
    pages = re.findall(r'<section class="page[^"]*">.*?</section>', html, flags=re.S)
    if not pages:
        raise SystemExit("Inga sidor hittades i guiden.")

    # The white back of the cover pushes every later page one step on.
    def shift(page: str) -> str:
        page = re.sub(r'(<div class="folio"><span>[^<]*</span><span>)(\d+)(</span>)',
                      lambda m: f"{m[1]}{int(m[2]) + 1}{m[3]}", page)
        # Table of contents: the page number is the last span of each row.
        return re.sub(r'(<li><span>\d+</span><span>[^<]*</span><span>)(\d+)(</span></li>)',
                      lambda m: f"{m[1]}{int(m[2]) + 1}{m[3]}", page)

    book = [pages[0], BLANK] + [shift(p) for p in pages[1:]]
    while len(book) % 4:
        book.append(BLANK)
    n = len(book)

    # Saddle stitch: each sheet carries two pages per side. Front of sheet k:
    # last-k | first+k; back: first+k+1 | last-k-1 (pages counted from 0).
    sides = []
    for k in range(n // 4):
        sides.append((book[n - 1 - 2 * k], book[2 * k]))
        sides.append((book[2 * k + 1], book[n - 2 - 2 * k]))

    style = """
<style>
@page { size: 297mm 210mm; margin: 0; }
.side { width: 297mm; height: 210mm; display: flex; page-break-after: always; overflow: hidden; }
.side:last-child { page-break-after: auto; }
.slot { width: 148.5mm; height: 210mm; overflow: hidden; position: relative; }
.slot > .page { page-break-after: auto; }
.page.blank { background: white; }
/* A thin fold mark at the top and bottom of the middle. */
.fold { position: absolute; left: 148.5mm; width: 0; height: 4mm; border-left: 0.2mm solid #b9b9b9; }
</style>
"""
    head = head.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    head = head.replace("<title>", "<title>TRYCK – ", 1)
    body = []
    for left, right in sides:
        body.append('<div class="side" style="position:relative">'
                    f'<div class="slot">{left}</div><div class="slot">{right}</div>'
                    '<div class="fold" style="top:0"></div><div class="fold" style="bottom:0"></div></div>')
    head = head.replace("</head>", style + "</head>", 1)
    OUT.write_text(head + "<body>\n" + "\n".join(body) + "\n</body>\n</html>\n", encoding="utf-8")
    print(f"{OUT.name}: {n} sidor på {n // 4} A4-ark ({len(sides)} sidor att skriva ut)")


if __name__ == "__main__":
    main()
