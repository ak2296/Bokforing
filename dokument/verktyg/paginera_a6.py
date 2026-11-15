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
.toc li { font-size: 9.2pt; padding: 1.5mm 0; }
.two, .two.left { display: block; }
.fl { display: flow-root; }
.fl > .shot { float: right; width: 38mm; margin: 0 0 2mm 4mm; }
.fl > .shot.l { float: left; margin: 0 4mm 2mm 0; }
.fl > .shot .phone { zoom: 0.76; }
.detail { font-size: 7.8pt; } .detail .cap { font-size: 7pt; } .ui small { font-size: 6.8pt; }
.num { width: 4.4mm; height: 4.4mm; font-size: 7pt; } .pill { font-size: 7pt; }
.detail[style*="grid"] { grid-template-columns: 1fr !important; }
.flow { flex-direction: column; } .flow .arr { transform: rotate(90deg); }
.cover .inner { padding: 14mm 9mm; } .cover h1 { font-size: 30pt; margin-top: 8mm; }
.cover .logo { width: 18mm; height: 18mm; } .cover .logo img { width: 18mm; height: 18mm; }
.cover .sub { font-size: 12pt; } .cover .tag { left: 9mm; bottom: 12mm; }
.cover .deco { right: -12mm; top: 62mm; transform: rotate(-12deg) scale(.74); transform-origin: top right; }
</style>
"""

SCRIPT = r"""
<script>
(function () {
  var MM = 96 / 25.4;
  function limit(page) { return page.clientHeight - 12 * MM; }
  function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }
  // The units a chapter is cut into. Lists and tables go row by row.
  function units(sec) {
    var out = [];
    Array.from(sec.children).forEach(function (c) {
      if (c.classList.contains('folio')) return;
      if (c.tagName === 'TABLE') {
        Array.from(c.querySelectorAll('tr')).forEach(function (r) {
          var t = c.cloneNode(false); var b = el('tbody'); t.appendChild(b);
          b.appendChild(r.cloneNode(true)); t.style.margin = '0'; out.push(t);
        });
      } else if (c.tagName === 'OL' || c.tagName === 'UL') {
        Array.from(c.children).forEach(function (li, i) {
          var l = c.cloneNode(false); l.appendChild(li.cloneNode(true)); l.style.margin = '0';
          if (c.tagName === 'OL' && c.classList.contains('steps')) l.style.counterReset = 's ' + i;
          else if (c.tagName === 'OL') l.start = i + 1;
          out.push(l);
        });
      } else if (c.classList.contains('two')) {
        var kids = Array.from(c.children);
        var shot = kids.filter(function (k) { return k.classList.contains('shot') || k.querySelector('.phone'); })[0];
        if (!shot || kids.length !== 2) { out.push(c.cloneNode(true)); return; }
        var txt = kids.filter(function (k) { return k !== shot; })[0];
        var wrap = el('div', 'fl'); var s = shot.cloneNode(true); s.classList.add('shot');
        if (kids.indexOf(shot) === 0) s.classList.add('l');
        wrap.appendChild(s); wrap.__txt = Array.from(txt.children); wrap.__shot = s;
        out.push(wrap);
      } else out.push(c.cloneNode(true));
    });
    return out;
  }
  function isHead(u) { return /^(H1|H2|H3)$/.test(u.tagName) || u.classList.contains('kicker'); }
  function paginate(sec) {
    if (sec.classList.contains('cover')) return [sec];
    var title = (sec.querySelector('.folio span') || {}).textContent || '';
    var pages = [], page;
    function fresh() { page = sec.cloneNode(false); sec.parentNode.insertBefore(page, sec); pages.push(page); }
    function fits(u) { return u.offsetTop + u.offsetHeight <= limit(page) + 0.5; }
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
      if (u.__txt) {
        // the phone sketch floats beside the first paragraphs, the rest follows as plain units
        var inner = el('div'); u.appendChild(inner);
        put(u);
        var rest = u.__txt.slice(), shotH = u.__shot.offsetHeight + 8;
        while (rest.length && inner.offsetHeight < shotH) {
          var c = rest.shift(); inner.appendChild(c);
          if (!fits(u)) { inner.removeChild(c); rest.unshift(c); break; }
        }
        rest.forEach(function (c) { put(c); });
      } else put(u);
    });
    pages.forEach(function (p) {
      var f = el('div', 'folio'); f.innerHTML = '<span></span><span></span>'; f.firstChild.textContent = title; p.appendChild(f);
    });
    sec.parentNode.removeChild(sec);
    return pages;
  }
  function run() {
    var all = [];
    Array.from(document.querySelectorAll('section.page')).forEach(function (s) { all = all.concat(paginate(s)); });
    // safety pass: anything still reaching into the bottom margin moves to a new page
    for (var q = 0; q < all.length; q++) {
      var pg = all[q];
      var kids = Array.from(pg.children).filter(function (c) { return !c.classList.contains('folio'); });
      var lim = pg.clientHeight - 12 * MM;
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
    all.forEach(function (p, i) { var f = p.querySelector('.folio'); if (f) f.lastChild.textContent = i + 1; });
    document.querySelectorAll('.toc li').forEach(function (li, i) {
      for (var k = 0; k < all.length; k++) {
        var kk = all[k].querySelector('.kicker');
        if (kk && kk.textContent.replace(/\s/g, '').indexOf((i + 1) + '\u00b7') === 0) { li.lastElementChild.textContent = k + 1; break; }
      }
    });
  }
  document.fonts.ready.then(function () { setTimeout(run, 50); });
})();
</script>
"""


def build() -> list[str]:
    """The guide as a list of A6 page sections (HTML), page numbers set."""
    html = SRC.read_text(encoding="utf-8")
    html = html.replace("@page { size: 148mm 210mm; margin: 0; }", "")
    html = html.replace("</head>", STYLE + "</head>", 1).replace("</body>", SCRIPT + "</body>", 1)
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
