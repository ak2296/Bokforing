"""Screenshots of the phone guide's pages, eight per picture (4 x 2):
python dokument/verktyg/granska_telefon.py OUTDIR"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide-telefon.html"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
out = pathlib.Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
tmp = SRC.with_name("_granska-tel.html")
html = SRC.read_text(encoding="utf-8").replace("</head>", """<style>
@page { size: 300mm 260mm; }
body { display: grid; grid-template-columns: repeat(4, 70mm); gap: 4mm; background: #888; margin: 0; width: 300mm; }
.page { page-break-after: auto !important; outline: 0.3mm solid #f00; }
</style></head>""", 1)
html = html.replace("</body>", """<script>
var n = parseInt((location.hash || '#1').slice(1), 10);
document.querySelectorAll('.page').forEach(function (p, i) { if (i < (n - 1) * 8 || i >= n * 8) p.style.display = 'none'; });
</script></body>""")
tmp.write_text(html, encoding="utf-8")
count = len(re.findall(r'<section class="page', html))
for k in range(1, (count + 7) // 8 + 1):
    target = out / f"tel-{k}.png"
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1.2",
                    "--window-size=1135,990", "--virtual-time-budget=4000", f"--screenshot={target}",
                    tmp.as_uri() + f"#{k}"], check=True, capture_output=True)
tmp.unlink()
print(count, "sidor")
