"""Puts the phone sketches from skisser.py into dokument/anvandarguide/anvandarguide.html
(replacing the old ones) and the CSS they need. Run after changing skisser.py:

    python dokument/verktyg/make_skisser.py
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import skisser as k  # noqa: E402

SRC = pathlib.Path(__file__).resolve().parents[1] / "anvandarguide/anvandarguide.html"

CSS = """/* ---------- Skisser som i appen (skisser.py) ---------- */
.screen .body { padding: 0 2.2mm; }
.two-c { display: flex; gap: 1.2mm; margin-bottom: 1.2mm; }
.two-c > .card { flex: 1; margin: 0; padding: 1.5mm; }
.card.amb { background: #FFF6E5; border-color: #F4E2BC; }
.ok { color: #0B6B4E; } .mu { color: #62706A; font-size: 4.6pt; } .am { color: #8A5300; font-weight: 500; }
.big { font-size: 7pt; font-weight: 500; } .big2 { font-size: 9pt; font-weight: 500; margin: 0.6mm 0 1mm; }
.row2 { display: flex; align-items: center; gap: 1.6mm; }
.vatic { width: 3.4mm; height: 3.4mm; border: 0.4mm solid #0B6B4E; border-radius: 0.8mm; flex: none; }
.card.amb .vatic { border-color: #8A5300; }
.fld { position: relative; background: #fff; border: 0.3mm solid #B4BFB9; border-radius: 1.6mm; padding: 1.5mm 1.8mm 1mm; margin: 2mm 0 1.4mm; }
.fld.warn-f { background: #FBE9D8; border-color: #E9B98A; }
.fld label { position: absolute; left: 1.6mm; top: -1.3mm; background: #F5F7F4; padding: 0 0.6mm; font-size: 4.2pt; color: #62706A; }
.fld.warn-f label { background: #FBE9D8; }
.fv { display: flex; align-items: center; gap: 1.2mm; font-size: 5.6pt; }
.fi { width: 2.8mm; height: 2.8mm; border: 0.4mm solid #0B6B4E; border-radius: 50%; flex: none; }
.fi.wa { border: 0; background: #E2600D; color: #fff; font-size: 4pt; text-align: center; line-height: 2.8mm; font-weight: 500; }
.fi.s { width: 2.4mm; height: 2.4mm; line-height: 2.4mm; }
.dt { font-weight: 500; margin: 1.2mm 0 0.4mm; }
.scan { display: flex; align-items: center; gap: 1.4mm; }
.pic { width: 3mm; height: 3mm; border: 0.4mm solid #0B6B4E; border-radius: 0.8mm; flex: none; }
.zr .zl { display: flex; align-items: center; gap: 1.2mm; padding: 0.9mm 0; border-top: 0.2mm solid #E8ECE6; font-size: 5pt; }
.zr .zl:first-of-type { margin-top: 1mm; }
.month { text-align: center; padding: 1mm; border: 0.25mm solid #E8ECE6; border-radius: 3mm; background: #fff; margin-bottom: 1.2mm; font-size: 5.4pt; }
.sec { font-weight: 500; margin: 1.2mm 0 0.8mm; display: flex; justify-content: space-between; }
.share { display: flex; gap: 0.3mm; height: 2mm; border-radius: 1mm; overflow: hidden; margin-bottom: 1mm; }
.share s { display: block; text-decoration: none; }
.legend b { margin-left: auto; font-weight: 400; color: #62706A; }
.outl { border: 0.4mm solid #0B6B4E; color: #0B6B4E; border-radius: 2mm; text-align: center; padding: 1.2mm; margin: 1.2mm 0; font-weight: 500; }
.btns { display: flex; gap: 1.2mm; margin-bottom: 1.2mm; } .btns span { flex: 1; text-align: center; border: 0.25mm solid #E8ECE6; background: #fff; border-radius: 1.6mm; padding: 0.9mm 0; }
.rl { display: flex; justify-content: space-between; padding: 0.7mm 0; } .rl.t { border-top: 0.2mm solid #E8ECE6; font-weight: 500; margin-top: 0.4mm; }
.pill-nav { position: absolute; left: 1.6mm; right: 1.6mm; bottom: 1.6mm; height: 7.4mm; background: #fff; border: 0.25mm solid #E8ECE6; border-radius: 3.7mm; display: flex; justify-content: space-around; align-items: center; font-size: 3.6pt; color: #62706A; box-shadow: 0 0.4mm 1.2mm rgba(0,0,0,.12); }
.pill-nav div { text-align: center; position: relative; } .pill-nav .ni { display: block; width: 2.6mm; height: 2.6mm; border: 0.4mm solid currentColor; border-radius: 0.7mm; margin: 0 auto 0.3mm; }
.pill-nav .sc { color: #0B6B4E; } .pill-nav .on { color: #E2600D; font-weight: 500; }
.pill-nav .on::before { content: ""; position: absolute; left: -1mm; right: -1mm; top: -1.5mm; height: 0.5mm; background: #E2600D; border-radius: 0.3mm; box-shadow: 0 1mm 1.6mm rgba(226,96,13,.5); }
.screen .hero.coral { margin-bottom: 1.2mm; }
.screen .hero { margin-bottom: 1.2mm; }
.mu2 { font-size: 4.6pt; opacity: .8; margin-bottom: 1mm; }
.seg { display: flex; } .seg i { font-style: normal; padding: 0 1mm; font-size: 4pt; border: 0.2mm solid #B4BFB9; } .seg i.on { background: #E4F2EC; color: #0B6B4E; }
"""

_over = [0]


def _oversikt() -> str:
    """The first overview sketch in the file is the small one on the cover."""
    _over[0] += 1
    return k.oversikt(small=_over[0] == 1)


BLOCKS = [  # (identifying text, new html)
    ("DIN RESTAURANG November 2026 Säkerhetskopia", _oversikt),
    ("DIN RESTAURANG November 2026 Resultat", _oversikt),
    ("Dokumenttyp: Faktura", k.kontrollera_faktura),
    ("Dokumenttyp: Z-rapport", k.kontrollera_z),
    ("Utgifter ‹", k.utgifter),
    ("Rapporter Månad", k.rapporter),
]


def end(s: str, i: int) -> int:
    depth = 0
    for m in re.finditer(r"<div\b|</div>", s[i:]):
        depth += 1 if m.group(0) != "</div>" else -1
        if depth == 0:
            return i + m.end()
    raise SystemExit("ofullständig block")


def main() -> None:
    s = SRC.read_text(encoding="utf-8")
    # one pass: find phone blocks, decide by their text, replace from the end
    spans = []
    for m in re.finditer(r'<div class="phone', s):
        e = end(s, m.start())
        txt = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s[m.start():e]))
        for key, make in BLOCKS:
            if key in txt:
                spans.append((m.start(), e, make))
                break
    for a, b, make in reversed(spans):
        s = s[:a] + make() + s[b:]
    s = re.sub(r"/\* ---------- Skisser som i appen.*?(?=\n/\* ---------- Omslag)", "", s, flags=re.S)
    s = s.replace("/* ---------- Omslag ---------- */", CSS + "\n/* ---------- Omslag ---------- */", 1)
    SRC.write_text(s, encoding="utf-8")
    print(len(spans), "skisser bytta")


if __name__ == "__main__":
    main()
