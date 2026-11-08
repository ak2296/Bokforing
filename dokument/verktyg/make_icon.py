"""Draws the Android app icon PNGs from dokument/logo/quee-ikon.svg with
Microsoft Edge (headless, already on Windows; nothing installed):

    python dokument/verktyg/make_icon.py

Writes android_icon/res (copied into the app by the GitHub build) and
dokument/bilder/app-ikon.png.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
LOGO = ROOT / "dokument/logo/quee-ikon.svg"
FOREGROUND = ROOT / "dokument/logo/quee-ikon-forgrund.svg"
RES = ROOT / "android_icon/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def render(svg: pathlib.Path, size: int, out: pathlib.Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / "icon.html"
        page.write_text(
            f'<html><body style="margin:0;background:transparent">'
            f'<img src="{svg.as_uri()}" style="width:{size}px;height:{size}px;display:block"></body></html>',
            encoding="utf-8")
        subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
                        f"--window-size={size},{size}", "--virtual-time-budget=2000", f"--screenshot={out}",
                        page.as_uri()], check=True, capture_output=True)


for name, factor in DENSITIES.items():
    render(LOGO, round(48 * factor), RES / f"mipmap-{name}/ic_launcher.png")
    render(FOREGROUND, round(108 * factor), RES / f"mipmap-{name}/ic_launcher_foreground.png")
render(LOGO, 192, ROOT / "dokument/bilder/app-ikon.png")
(RES / "values/ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0B6B4E</color>\n</resources>\n',
    encoding="utf-8")
print("Ikoner klara")
