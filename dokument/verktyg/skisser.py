"""The phone sketches of the user guide, drawn to match the app as it is now
(light theme): header with a gear, half-width cards on the overview, outlined
fields with a status icon on the review screens, and the floating tab bar.
make_skisser.py puts them into anvandarguide.html.
"""

NAV_ICON = '<i class="ni"></i>'


def nav(active: int) -> str:
    names = ["Översikt", "Försälj.", "Skanna", "Utgifter", "Rapporter"]
    out = []
    for i, n in enumerate(names):
        cls = "on" if i == active else ""
        scan = " sc" if i == 2 else ""
        out.append(f'<div class="{cls}{scan}">{NAV_ICON}{n}</div>')
    return '<div class="pill-nav">' + "".join(out) + "</div>"


def status() -> str:
    return '<div class="bar"><span>09:41</span><span>●●●</span></div>'


def head(title: str, sub: str = "", back: bool = False) -> str:
    left = ("‹ " if back else "") + title
    s = f"<small>{sub}</small>" if sub else ""
    gear = "" if back else '<div class="gear"></div>'
    return f'<div class="apphead"><div>{left}{s}</div>{gear}</div>'


def phone(inner: str, small: bool = False) -> str:
    cls = "phone small" if small else "phone"
    return f'<div class="{cls}"><div class="screen">{inner}</div></div>'


def bars() -> str:
    cols = [(55, 35), (70, 40), (60, 45), (85, 38), (75, 50), (95, 42)]
    return '<div class="bars">' + "".join(
        f'<div><s style="height:{a}%"></s><s style="height:{b}%"></s></div>' for a, b in cols) + "</div>"


def oversikt(small: bool = False) -> str:
    body = f"""<div class="body">
  <div class="rkrow"><span class="rk">Räkningar <b>3</b></span></div>
  <div class="hero"><div>Resultat före skatt</div><div class="big2">−32 867 kr</div><div class="mu2">Exkl. moms</div>
    <div class="stats"><div>Försäljning<b>42 460</b></div><div>Utgifter<b>75 327</b></div></div></div>
  <div class="card row2"><span class="vatic"></span><div><span class="mu">Moms att betala i november (beräknad)</span><br><b class="big">2 492 kr</b></div></div>
  <div class="card"><div class="sec"><span class="mu">Försäljning och utgifter</span><span class="seg"><i class="on">Månader</i><i>Veckodag</i></span></div>{bars()}</div>
</div>"""
    header = '<div class="apphead"><div>DIN RESTAURANG<small>November 2026</small></div><div class="hr"><span class="cl">&#9679;</span><span class="cl">&#9729;</span><div class="gear"></div></div></div>'
    return phone(status() + header + body + nav(0), small)


def field(label: str, value: str, state: str = "ok", right: str = "") -> str:
    icon = {"ok": '<span class="fi ok"></span>', "warn": '<span class="fi wa">!</span>', "": ""}[state]
    cls = " warn-f" if state == "warn" else ""
    return (f'<div class="fld{cls}"><label>{label}</label><div class="fv">{icon}<span class="grow">{value}</span>{right}</div></div>')


def kontrollera_faktura() -> str:
    body = f"""<div class="body">
  <div class="card scan"><span class="pic"></span><div><b>Skannat dokument</b><br><span class="mu">Tryck för att jämföra med bilden</span></div><span class="mu">⌃</span></div>
  <div class="dt">Dokumenttyp: Faktura</div>
  {field("Datum", "2026-10-16", "ok", '<span class="mu">▦</span>')}
  {field("Leverantör", "Telefon och internet", "warn")}
  {field("Kostnadstyp", "Ej vald", "", '<span class="mu">▾</span>')}
  {field("Summa (att betala)", "1 433,00 kr", "ok")}
  {field("Moms", "286,50 kr", "ok")}
  <div class="save">✓ Godkänn och spara</div>
  <div class="links"><span>Skanna igen</span><span>Avbryt</span></div>
</div>"""
    return phone(status() + head("Kontrollera uppgifterna", back=True) + body)


def kontrollera_z() -> str:
    body = f"""<div class="body">
  <div class="card scan"><span class="pic"></span><div><b>Skannat dokument</b><br><span class="mu">Tryck för att jämföra med bilden</span></div><span class="mu">⌄</span></div>
  <div class="dt">Dokumenttyp: Z-rapport</div>
  {field("Datum", "2026-11-02", "ok", '<span class="mu">▦</span>')}
  <div class="card zr"><b>Försäljning per kategori</b>
    <div class="zl"><span class="fi ok s"></span><span class="grow">Avhämtning<br><span class="mu">Räknas som Avhämtning · 6 %</span></span><b>932,00</b></div>
    <div class="zl"><span class="fi ok s"></span><span class="grow">Mat<br><span class="mu">Räknas som Mat · 12 %</span></span><b>661,00</b></div>
    <div class="zl"><span class="fi wa s">!</span><span class="grow">Tobak<br><span class="mu">Kontrollera</span></span><b>786,00</b></div>
    <div class="zl"><span class="fi ok s"></span><span class="grow">Drycka<br><span class="mu">Räknas som Dryck · 12 %</span></span><b>80,00</b></div>
  </div>
  <div class="card"><b>Beräknad moms</b><br><span class="mu">25 %: 157,20 · 12 %: 79,39 · 6 %: 52,75</span></div>
  <div class="save">✓ Godkänn och spara</div>
</div>"""
    return phone(status() + head("Kontrollera uppgifterna", back=True) + body)


def utgifter() -> str:
    body = f"""<div class="body">
  <div class="month">‹ &nbsp; ▦ November 2026 &nbsp; ›</div>
  <div class="card amb row2"><span class="vatic"></span><div><b class="am">Att betala: 3 fakturor</b><br><span class="mu">Förfallit: 1</span></div><b class="am">12 480 kr</b></div>
  <div class="hero coral"><div>Utgifter</div><div class="big2">21 506,40 kr</div>
    <div class="stats"><div>Ingående moms<b>3 410</b></div><div>Fakturor<b>9</b></div><div>Obetalda<b>2</b></div></div></div>
  <div class="sec">Per kostnadstyp <span class="mu">exkl. moms</span></div>
  <div class="card"><div class="share"><s style="flex:62;background:#E2600D"></s><s style="flex:20;background:#F2832E"></s><s style="flex:10;background:#F9B27A"></s><s style="flex:8;background:#8A5300"></s></div>
    <div class="legend"><i style="background:#E2600D"></i>Varuinköp<b>62 %</b></div><div class="legend"><i style="background:#F2832E"></i>Telefon<b>20 %</b></div></div>
  <div class="outl">Matcha betalningar från bankfil</div>
</div>"""
    return phone(status() + head("Utgifter") + body + nav(3))


def rapporter() -> str:
    body = f"""<div class="body">
  <div class="tabs"><div>Månad</div><div>År</div><div class="on">Resultat</div><div>Jämför</div></div>
  <div class="month">‹ &nbsp; November 2026 &nbsp; ›</div>
  <div class="btns"><span>PDF</span><span>Excel</span><span>Skriv ut</span></div>
  <div class="card"><div class="rl"><span>Försäljning exkl. moms</span><b>35 745</b></div><div class="rl"><span>Utgifter exkl. moms</span><b>−61 652</b></div><div class="rl t"><span>Resultat före skatt</span><b>−25 907</b></div></div>
  <div class="card"><div class="rl"><span>Totala utgifter</span><b>75 327</b></div><div class="rl"><span>Utgående moms</span><b>6 715</b></div><div class="rl"><span>Ingående moms</span><b>13 674</b></div><div class="rl t"><span>Moms att få tillbaka</span><b>6 959</b></div></div>
  <div class="outl">SIE-fil till redovisaren</div>
</div>"""
    return phone(status() + head("Rapporter") + body + nav(4))
