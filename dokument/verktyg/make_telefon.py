"""Makes the phone version of the user guide (the one the app opens): the same
text as anvandarguide.html, set for a phone's width. The PDF page is 70 mm wide,
about as wide as a phone screen, so the text is shown at its real size (a
reader fits the page width to the screen).

Each chapter is ONE tall page (as tall as the chapter), so the reader scrolls
a chapter without any page break through a sentence or a sketch, and swipes
to the next chapter. The heights are measured with Microsoft Edge first.

    python dokument/verktyg/make_telefon.py
"""
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
OUT = ROOT / "dokument/anvandarguide/anvandarguide-telefon.html"
TMP = ROOT / "dokument/anvandarguide/_telefon-matt.html"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

W = 70  # mm
COVER_H = 165

STYLE = f"""
<style>
body {{ font-size: 10.5pt; line-height: 1.5; }}
.page {{ width: {W}mm; height: auto; min-height: 0; padding: 7mm 5.5mm 8mm; overflow: hidden; page-break-after: always; }}
.page:last-child {{ page-break-after: auto; }}
.folio {{ display: none; }}
h1 {{ font-size: 17pt; line-height: 1.15; margin-bottom: 3mm; }}
h2 {{ font-size: 13pt; margin: 6mm 0 2mm; }}
h3 {{ font-size: 11.5pt; }}
.kicker {{ font-size: 8.5pt; }}
.lead {{ font-size: 10.5pt; }}
ul, ol {{ padding-left: 5mm; }}
.tip, .warn {{ font-size: 9.8pt; padding: 3mm 3.5mm; margin: 3.5mm 0; }}
.kbd, .btn {{ font-size: 9.6pt; }}
.steps li {{ padding-left: 8.5mm; }}
.steps li::before {{ width: 5.6mm; height: 5.6mm; font-size: 8.5pt; }}
.toc li {{ font-size: 10.5pt; }}
.toc li span:last-child {{ display: none; }}
.toc li {{ padding: 3mm 0; }}
.toc a {{ color: var(--green); text-decoration: none; display: block; }}
.toc li span:nth-child(2) a::after {{ content: ' ›'; color: var(--muted); }}

/* tables become stacked rows: label above, text below */
table.t, table.t tbody, table.t tr, table.t td, table.t th {{ display: block; width: auto !important; }}
table.t {{ font-size: 10pt; }}
table.t tr {{ padding: 2mm 0; border-bottom: 0.3mm solid var(--line); }}
table.t tr:has(th) {{ display: none; }}
table.t td {{ border: 0; padding: 0; }}
table.t td:first-child {{ color: var(--green); font-size: 9.4pt; margin-bottom: 0.6mm; }}

/* two columns become one: the text first, then the sketch */
.two, .two.left {{ display: flex; flex-direction: column; }}
.two > .shot, .two > .phone, .two > div:has(> .phone) {{ order: 2; width: 46mm; margin: 3mm auto 1mm; }}
.shot {{ width: 46mm; margin: 3mm auto; }}
.detail {{ font-size: 8.8pt; }}
.detail .cap {{ font-size: 8pt; }}
.detail[style*="grid"] {{ grid-template-columns: 1fr !important; }}
.ui small {{ font-size: 7.6pt; }}
.flow {{ flex-direction: column; }}
.flow .arr {{ transform: rotate(90deg); }}
.num {{ width: 5mm; height: 5mm; font-size: 8pt; }}
.pill {{ font-size: 7.6pt; }}
.cover {{ height: {COVER_H}mm; overflow: hidden; }}
.cover .inner {{ padding: 10mm 6mm; }}
.cover .logo {{ width: 18mm; height: 18mm; }} .cover .logo img {{ width: 18mm; height: 18mm; }}
.cover h1 {{ font-size: 30pt; margin-top: 7mm; }}
.cover .sub {{ font-size: 13pt; }}
.cover .deco {{ right: -3mm; top: 74mm; transform: rotate(-12deg); transform-origin: top right; }} .cover .deco img {{ width: 39mm !important; height: 78mm !important; }}
.cover .tag {{ position: static; margin-top: 3mm; font-size: 8.5pt; }}
</style>
"""

MEASURE = """<script>
document.fonts.ready.then(function () { setTimeout(function () {
  var h = Array.from(document.querySelectorAll('section.page')).map(function (s) { return s.getBoundingClientRect().height * 25.4 / 96; });
  document.body.setAttribute('data-h', JSON.stringify(h));
}, 100); });
</script>"""


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    html = html.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    html = re.sub(r"<title>.*?</title>", "<title>Quee – Användarguide (telefon)</title>", html, count=1)
    html = html.replace("</head>", STYLE + "</head>", 1)
    TMP.write_text(html.replace("</body>", MEASURE + "</body>", 1), encoding="utf-8")
    try:
        dom = subprocess.run([EDGE, "--headless", "--disable-gpu", f"--window-size={round(W * 96 / 25.4)},900", "--dump-dom",
                              "--virtual-time-budget=6000", TMP.as_uri()], check=True, capture_output=True).stdout.decode("utf-8")
    finally:
        TMP.unlink(missing_ok=True)
    heights = json.loads(re.search(r"data-h=\"([^\"]*)\"", dom).group(1).replace("&quot;", '"'))
    # one named page per chapter, as tall as the chapter (+1 mm so nothing spills)
    rules = ["<style>@page { margin: 0; }"]
    for i, h in enumerate(heights):
        size = COVER_H if i == 0 else int(h) + 2
        rules.append(f"@page c{i} {{ size: {W}mm {size}mm; margin: 0; }} section.page:nth-of-type({i + 1}) {{ page: c{i}; }}")
    rules.append("</style>")
    OUT.write_text(html.replace("</head>", "\n".join(rules) + "</head>", 1), encoding="utf-8")
    print(OUT.name, len(heights), "kapitel, högst", round(max(heights)), "mm")


if __name__ == "__main__":
    main()
