"""Screenshots of the booklet pages, six per picture (3 x 2), for checking the
layout:  python dokument/verktyg/granska_hafte.py OUTDIR
Uses the A6 print file (anvandarguide-A6-tryckfil.html)."""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide-A6-tryckfil.html"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
out = pathlib.Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
tmp = SRC.with_name("_granska.html")
html = SRC.read_text(encoding="utf-8").replace("</head>", """<style>
@page { size: 340mm 313mm; }
body { display: grid; grid-template-columns: repeat(3, 111mm); gap: 4mm; background: #888; margin: 0; width: 340mm; }
.bl { page-break-after: auto !important; outline: 0.3mm solid #f00; }
</style></head>""", 1)
html = html.replace("</body>", """<script>
var n = parseInt((location.hash || '#1').slice(1), 10);
document.querySelectorAll('.bl').forEach(function (p, i) { if (i < (n - 1) * 6 || i >= n * 6) p.style.display = 'none'; });
</script></body>""")
tmp.write_text(html, encoding="utf-8")
count = len(re.findall(r'class="bl"', html))
for k in range(1, (count + 5) // 6 + 1):
    target = out / f"hafte-{k}.png"
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1.3",
                    "--window-size=1285,1185", "--virtual-time-budget=4000", f"--screenshot={target}",
                    tmp.as_uri() + f"#{k}"], check=True, capture_output=True)
tmp.unlink()
print(count, "sidor")
