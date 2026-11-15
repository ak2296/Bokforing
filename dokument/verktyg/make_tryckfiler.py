"""Makes the packaging files a printing company needs from forpackning.html:

  forpackning-tryckfil.html  artwork only (colours with 3 mm bleed, no lines,
                             no labels), A4 landscape, 1:1
  forpackning-stans.html     the cut and fold lines only, same size and
                             position, to lay over the artwork

    python dokument/verktyg/make_tryckfiler.py
"""
import pathlib
import re

DIR = pathlib.Path(__file__).resolve().parents[1] / "forpackning"
SRC = DIR / "forpackning.html"

# The box with flaps and bleed spans x 25..278 and y 22..231 mm on the 420 x 297
# design sheet. Moved so it is centred on A4 landscape (297 x 210 mm).
SHIFT = (-3, -21.5)
BASE = f"""<style>
@page {{ size: 297mm 210mm; margin: 0; }}
.sheet:first-of-type {{ width: 297mm; height: 210mm; }}
.sheet:first-of-type > * {{ transform: translate({SHIFT[0]}mm, {SHIFT[1]}mm); }}
.preview {{ display: none !important; }}
html, body {{ height: 210mm; overflow: hidden; }}
.sheet:first-of-type {{ page-break-after: auto !important; }}
"""


def make(name: str, extra: str) -> None:
    html = SRC.read_text(encoding="utf-8")
    html = re.sub(r"<title>.*?</title>", f"<title>Quee förpackning – {name}</title>", html, count=1)
    html = html.replace("</head>", BASE + extra + "</style></head>", 1)
    (DIR / f"forpackning-{name}.html").write_text(html, encoding="utf-8")


make("tryckfil", "svg.die, .label { display: none !important; }\n")
make("stans", ".abs, .abs * { visibility: hidden !important; } svg.die { visibility: visible !important; } .label { display: none !important; }\n")
print("förpackning: tryckfil + stans")
