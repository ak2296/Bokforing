"""Makes the phone version of the user guide (the one the app opens): the same
text as anvandarguide.html, set for a phone's width. The PDF page is 70 mm wide,
about as wide as a phone screen, so the text is shown at its real size (a
reader fits the page width to the screen). Pages flow instead of having a
fixed height.

    python dokument/verktyg/make_telefon.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
OUT = ROOT / "dokument/anvandarguide/anvandarguide-telefon.html"

STYLE = """
<style>
@page { size: 70mm 140mm; margin: 0; }
body { font-size: 10.5pt; line-height: 1.5; }
.page { width: 70mm; height: auto; min-height: 0; padding: 7mm 5.5mm 9mm; overflow: visible; }
.folio { display: none; }
h1 { font-size: 17pt; line-height: 1.15; margin-bottom: 3mm; }
h2 { font-size: 13pt; margin: 6mm 0 2mm; }
h3 { font-size: 11.5pt; }
.kicker { font-size: 8.5pt; }
.lead { font-size: 10.5pt; }
p, li, .tip, .warn, .detail, table.t tr, .ui, .toc li { break-inside: avoid; }
h1, h2, h3, .kicker { break-after: avoid; }
ul, ol { padding-left: 5mm; }
.tip, .warn { font-size: 9.8pt; padding: 3mm 3.5mm; }
.kbd, .btn { font-size: 9.6pt; }
.steps li { padding-left: 8.5mm; }
.steps li::before { width: 5.6mm; height: 5.6mm; font-size: 8.5pt; }
.toc li { font-size: 10.5pt; }
.toc li span:last-child { display: none; }

/* tables become stacked rows: label above, text below */
table.t, table.t tbody, table.t tr, table.t td, table.t th { display: block; width: auto !important; }
table.t { font-size: 10pt; }
table.t tr { padding: 2mm 0; border-bottom: 0.3mm solid var(--line); }
table.t tr:has(th) { display: none; }
table.t td { border: 0; padding: 0; }
table.t td:first-child { color: var(--green); font-size: 9.4pt; margin-bottom: 0.6mm; }

/* two columns become one */
.two, .two.left { display: block; }
.shot { width: 50mm; margin: 3mm auto; }
.two > .shot { order: -1; }
.detail { font-size: 8.8pt; }
.detail .cap { font-size: 8pt; }
.ui small { font-size: 7.6pt; }
.flow { flex-direction: column; }
.flow .arr { transform: rotate(90deg); }
.num { width: 5mm; height: 5mm; font-size: 8pt; }
.pill { font-size: 7.6pt; }
.cover { height: 140mm; overflow: hidden; }
.cover .inner { padding: 10mm 6mm; }
.cover .logo { width: 18mm; height: 18mm; } .cover .logo img { width: 18mm; height: 18mm; }
.cover h1 { font-size: 30pt; margin-top: 7mm; }
.cover .sub { font-size: 13pt; }
.cover .deco { right: -10mm; top: 66mm; transform: rotate(-12deg) scale(.62); transform-origin: top right; }
.cover .tag { left: 6mm; bottom: 8mm; font-size: 8.5pt; }
</style>
"""


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    head = html[: html.index("<body>")]
    head = head.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    head = re.sub(r"<title>.*?</title>", "<title>Quee – Användarguide (telefon)</title>", head, count=1)
    head = head.replace("</head>", STYLE + "</head>", 1)
    body = html[html.index("<body>"):]
    show = ("<script>var n = parseInt((location.hash || '').replace('#s', ''), 10);"
            "if (n) document.querySelectorAll('.page').forEach(function (s, i) { if (i !== n - 1) s.style.display = 'none'; });"
            "</script>")
    OUT.write_text(head + body.replace("</body>", show + "</body>"), encoding="utf-8")
    print(OUT.name)


if __name__ == "__main__":
    main()
