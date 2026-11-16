"""Sets the user guide for A6 paper at real size (not shrunk from A5) and
splits it into fixed A6 pages with Microsoft Edge (headless). Used by
make_booklet.py.

The guide's text and sketches are the same as in the A5 and phone versions;
only the type sizes and the layout are set for A6 (body 8.8 pt). Each chapter
is a flowing text that is cut into pages of 105 x 148.5 mm, unit by unit, so
a paragraph, a table row or a list item is never cut in two. Page numbers and
the contents list are filled in afterwards.
"""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "dokument/anvandarguide/anvandarguide.html"
TMP = ROOT / "dokument/anvandarguide/_a6-kalla.html"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

STYLE = """
<style>
@page { size: 105mm 148.5mm; margin: 0; }
body { font-size: 8.8pt; line-height: 1.45; }
.page { width: 105mm; height: 148.5mm; padding: 9mm 8mm 12mm; overflow: hidden; }
.folio { left: 8mm; right: 8mm; bottom: 5mm; font-size: 7pt; }
h1 { font-size: 15pt; line-height: 1.15; margin-bottom: 2.5mm; }
h2 { font-size: 11pt; margin: 4mm 0 1.5mm; } h3 { font-size: 9.6pt; }
.kicker { font-size: 7.6pt; } .lead { font-size: 9pt; margin-bottom: 3mm; }
.tip, .warn { font-size: 8.4pt; padding: 2.2mm 3mm; margin: 2.5mm 0; }
.kbd, .btn { font-size: 8.2pt; }
.steps li { padding-left: 7.5mm; margin-bottom: 1.6mm; }
.steps li::before { width: 5mm; height: 5mm; font-size: 7.5pt; }
table.t { font-size: 8.4pt; table-layout: fixed; } table.t th { font-size: 7.4pt; }
table.t td:first-child, table.t th:first-child { width: 27mm; }
.toc li { font-size: 8.6pt; padding: 0.6mm 0; }
.toc { margin-top: 2mm; }
.two, .two.left { display: block; }
.fl { display: flow-root; }
.fl > .shot { float: right; width: 50mm; zoom: 0.62; margin: 0 0 3mm 6mm; }
.fl > .shot.l { float: left; margin: 0 6mm 3mm 0; }
.detail { font-size: 7.8pt; } .detail .cap { font-size: 7pt; } .ui small { font-size: 6.8pt; }
.num { width: 4.4mm; height: 4.4mm; font-size: 7pt; } .pill { font-size: 7pt; }
.detail[style*="grid"] { grid-template-columns: 1fr !important; }
.flow .ui { padding: 1.2mm 1.4mm; font-size: 7pt; } .flow .arr { font-size: 7pt; }
.flow .sw { width: 6mm; }
.cover .inner { padding: 14mm 9mm; } .cover h1 { font-size: 30pt; margin-top: 8mm; }
.cover .logo { width: 18mm; height: 18mm; } .cover .logo img { width: 18mm; height: 18mm; }
.cover .sub { font-size: 12pt; } .cover .tag { left: 9mm; bottom: 12mm; }
.cover .deco { right: -13mm; top: 52mm; transform: rotate(-12deg) scale(.71); transform-origin: top right; }
.trow { display: grid; grid-template-columns: 24mm 1fr; gap: 2mm; padding: 1.3mm 0; border-bottom: 0.3mm solid var(--line); font-size: 8.4pt; line-height: 1.35; }
.trow > div:first-child { font-weight: 500; }
.fl .trow { grid-template-columns: 19mm 1fr; }
</style>
"""

SCRIPT = r"""
<script>
(function () {
  var MM = 96 / 25.4;
  function limit(page) { return page.clientHeight - CFG.bottom * MM; }
  function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
  // The units a chapter is cut into. Lists and tables go row by row.
  // A block cut into the pieces it may be split into: tables row by row, lists item by item.
  function pieces(c) {
    var out = [];
    if (c.tagName === 'TABLE') {
      // a table row becomes a grid row, so it can sit beside a sketch
      Array.from(c.querySelectorAll('tr')).forEach(function (r) {
        if (r.querySelector('th')) return;
        var d = el('div', 'trow');
        Array.from(r.children).forEach(function (cell) { var x = el('div'); x.innerHTML = cell.innerHTML; d.appendChild(x); });
        out.push(d);
      });
    } else if (c.tagName === 'OL' || c.tagName === 'UL') {
      Array.from(c.children).forEach(function (li, i) {
        var l = c.cloneNode(false); l.appendChild(li.cloneNode(true)); l.style.margin = '0';
        if (c.tagName === 'OL' && c.classList.contains('steps')) l.style.counterReset = 's ' + i;
        else if (c.tagName === 'OL') l.start = i + 1;
        out.push(l);
      });
    } else out.push(c.cloneNode(true));
    return out;
  }
  function units(sec) {
    var out = [];
    Array.from(sec.children).forEach(function (c) {
      if (c.classList.contains('folio')) return;
      if (c.classList.contains('two')) {
        var kids = Array.from(c.children);
        var shot = kids.filter(function (k) { return k.classList.contains('shot') || k.classList.contains('phone') || k.querySelector('.phone'); })[0];
        if (!shot || kids.length !== 2) { out.push(c.cloneNode(true)); return; }
        var txt = kids.filter(function (k) { return k !== shot; })[0];
        var wrap = el('div', 'fl'); var s = shot.cloneNode(true); s.classList.add('shot');
        if (kids.indexOf(shot) === 0) s.classList.add('l');
        wrap.appendChild(s);
        var tp = [].concat.apply([], Array.from(txt.children).map(pieces));
        if (CFG.stack) { tp.forEach(function (x) { out.push(x); }); out.push(wrap); return; }
        wrap.__txt = tp;
        wrap.__shot = s;
        out.push(wrap);
      } else pieces(c).forEach(function (x) { out.push(x); });
    });
    return out;
  }
  function isHead(u) { return /^(H1|H2|H3)$/.test(u.tagName) || u.classList.contains('kicker'); }
  function layout(sec, z, cap) {
    var pages = [], page;
    function fresh() { page = sec.cloneNode(false); sec.parentNode.insertBefore(page, sec); pages.push(page); }
    function fits(u) { return u.offsetTop + u.offsetHeight <= limit(page) * cap + 0.5; }
    function put(u) {
      page.appendChild(u);
      if (fits(u)) return;
      var moved = [page.removeChild(u)];
      // keep headings together with what follows them
      while (page.lastChild && isHead(page.lastChild) && page.children.length > 1) moved.unshift(page.removeChild(page.lastChild));
      fresh();
      moved.forEach(function (m) { page.appendChild(m); });
    }
    fresh();
    units(sec).forEach(function (u) {
      if (z < 1) u.style.zoom = z;
      if (u.__txt) {
        // the phone sketch floats beside the first paragraphs, the rest follows as plain units
        var inner = el('div'); u.appendChild(inner);
        put(u);
        var rest = u.__txt.slice(), shotH = u.__shot.offsetHeight + 8;
        while (rest.length && inner.offsetHeight < shotH) {
          var c = rest.shift(); inner.appendChild(c);
          if (!fits(u)) { inner.removeChild(c); rest.unshift(c); break; }
        }
        // a heading is not left last beside the sketch
        while (inner.lastChild && isHead(inner.lastChild) && inner.children.length > 1) rest.unshift(inner.removeChild(inner.lastChild));
        rest.forEach(function (c) { if (z < 1) c.style.zoom = z; put(c); });
      } else put(u);
    });
    return pages;
  }
  function drop(pages) { pages.forEach(function (p) { p.parentNode.removeChild(p); }); }
  // How full the emptiest page is, 0..1 (the last child's bottom against the usable height).
  function minFill(pages) {
    var m = 1;
    pages.forEach(function (p) {
      var kids = Array.from(p.children).filter(function (c) { return !c.classList.contains('folio'); });
      var last = kids[kids.length - 1];
      m = Math.min(m, last ? (last.offsetTop + last.offsetHeight) / limit(p) : 0);
    });
    return m;
  }
  // A chapter is set at full size; if a few lines spill onto an extra page it is
  // set a little smaller (down to 88 %): the size with the fewest pages wins.
  // Then the break is moved up so that no page is left with only a line or a
  // box: the setting with the most even pages wins.
  function paginate(sec) {
    if (sec.classList.contains('cover')) return [sec];
    var title = (sec.querySelector('.folio span') || {}).textContent || '';
    var bestZ = 1, bestN = 1e9;
    [1, 0.96, 0.92, 0.88].forEach(function (z) {
      var pages = layout(sec, z, 1);
      if (pages.length < bestN) { bestN = pages.length; bestZ = z; }
      drop(pages);
    });
    var best = layout(sec, bestZ, 1), bestFill = minFill(best);
    if (bestFill >= 0.3) { /* full pages, the last one may be short */ }
    else [0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6].forEach(function (cap) {
      var pages = layout(sec, bestZ, cap);
      var f = pages.length === bestN ? minFill(pages) : -1;
      if (f > bestFill + 0.005) { if (best) drop(best); best = pages; bestFill = f; } else drop(pages);
    });
    var pages = best;
    pages.forEach(function (p) {
      var f = el('div', 'folio'); f.innerHTML = '<span></span><span></span>'; f.firstChild.textContent = title; p.appendChild(f);
    });
    sec.parentNode.removeChild(sec);
    return pages;
  }
  function run() {
    var all = [];
    Array.from(document.querySelectorAll('section.page')).forEach(function (s) { all = all.concat(paginate(s)); });
    // a heading never ends a page: it goes to the next page of the same chapter
    for (var h = 0; h < all.length - 1; h++) {
      var kk2 = Array.from(all[h].children).filter(function (c) { return !c.classList.contains('folio'); });
      var lastKid = kk2[kk2.length - 1];
      var same = all[h + 1].querySelector('.folio span') && all[h].querySelector('.folio span') &&
        all[h + 1].querySelector('.folio span').textContent === all[h].querySelector('.folio span').textContent;
      if (lastKid && kk2.length > 1 && same && isHead(lastKid)) all[h + 1].insertBefore(lastKid, all[h + 1].firstChild);
    }
    // safety pass: anything still reaching into the bottom margin moves to a new page
    for (var q = 0; q < all.length; q++) {
      var pg = all[q];
      var kids = Array.from(pg.children).filter(function (c) { return !c.classList.contains('folio'); });
      var lim = pg.clientHeight - CFG.bottom * MM;
      for (var j = kids.length - 1; j > 0 && kids[j].offsetTop + kids[j].offsetHeight > lim + 0.5; j--) {
        var nxt = all[q + 1];
        if (!nxt || nxt.__title !== pg.querySelector('.folio span').textContent) {
          nxt = pg.cloneNode(false); nxt.__title = pg.querySelector('.folio span').textContent;
          var f2 = pg.querySelector('.folio').cloneNode(true); nxt.appendChild(f2);
          pg.parentNode.insertBefore(nxt, pg.nextSibling); all.splice(q + 1, 0, nxt);
        }
        nxt.insertBefore(kids[j], nxt.firstChild);
      }
    }
    all.forEach(function (p, i) { var f = p.querySelector('.folio'); if (f) f.lastChild.textContent = i + 2; });
    document.querySelectorAll('.toc li').forEach(function (li, i) {
      for (var k = 0; k < all.length; k++) {
        var kk = all[k].querySelector('.kicker');
        if (kk && kk.textContent.replace(/\s/g, '').indexOf((i + 1) + '\u00b7') === 0) { li.lastElementChild.textContent = k + 2; break; }
      }
    });
  }
  document.fonts.ready.then(function () { setTimeout(run, 50); });
})();
</script>
"""


def build(style: str = STYLE, bottom: float = 12, stack: bool = False) -> list[str]:
    """The guide as a list of A6 page sections (HTML), page numbers set."""
    html = SRC.read_text(encoding="utf-8")
    html = html.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    cfg = f"<script>var CFG = {{bottom: {bottom}, stack: {str(stack).lower()}}};</script>"
    html = html.replace("</head>", style + "</head>", 1).replace("</body>", cfg + SCRIPT + "</body>", 1)
    TMP.write_text(html, encoding="utf-8")
    try:
        out = subprocess.run([EDGE, "--headless", "--disable-gpu", "--dump-dom", "--virtual-time-budget=8000", TMP.as_uri()],
                             check=True, capture_output=True).stdout.decode("utf-8")
    finally:
        TMP.unlink(missing_ok=True)
    pages = re.findall(r'<section class="page[^"]*"[^>]*>.*?</section>', out, flags=re.S)
    if len(pages) < 4:
        raise SystemExit("A6-uppdelningen misslyckades.")
    return pages


if __name__ == "__main__":
    print(len(build()), "sidor")
