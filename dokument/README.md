# Dokument

Användarguide, nedladdningskort och förpackning för appen Quee.

| Mapp | Innehåll |
|---|---|
| `anvandarguide/` | Användarguiden: HTML-källan `anvandarguide.html` (A5, 15 sidor; ur den görs de andra), telefonversionen `anvandarguide-telefon.pdf` (70 mm bred, samma som i appen) och häftet för utskrift i A6: `anvandarguide-tryck.pdf` |
| `kort/` | Kort 55 × 85 mm (stående) med QR-kod, fram- och baksida |
| `forpackning/` | Tuck-box 109 × 152 × 7 mm för A6-häftet med kortet ovanpå: tryckfil med stans- och biglinjer (A3) och förhandsvisning |
| `bilder/` | Appikon och QR-koden till nedladdningssidan |
| `forhandsvisning/` | Bilder av utvalda sidor |
| `verktyg/` | Skript som gör PDF-filerna och förhandsbilderna med Microsoft Edge |

Gör om PDF-filerna efter en ändring:

```bash
python dokument/verktyg/make_docs.py
```

QR-koden leder till https://ak2296.github.io/quee/, där den senaste versionen av appen kan laddas ner.

Ändringar i den här mappen startar inget nytt bygge av appen.

## Skriv ut användarguiden som häfte

Häftet är A6 (105 × 148 mm) med text i verklig storlek (8,8 pt), inte förminskad från A5. Allt finns i en fil, `anvandarguide/anvandarguide-tryck.pdf`: 36 sidor på 5 A4-ark, fyra sidor per arksida. Framsidan, guiden, två sidor "Anteckningar" och baksidan; insidan av fram- och baksidan är vit.

1. Skriv ut **dubbelsidigt**, vänd längs **långsidan**, i **verklig storlek (100 %)**.
2. Skär varje A4-ark mitt itu på bredden (de små strecken, 6 mm från kanten, visar var). Det sista arkets nedre halva kan vara tom, förutom en mätskala (se nedan), och kan slängas.
3. Lägg halvorna i den ordning de skrevs ut, med första arkets övre halva ytterst.
4. Vik allt på mitten (strecken visar mitten) och häfta två gånger i vikningen.

### Om baksidan hamnar vid sidan av framsidan

Alla dubbelsidiga skrivare lägger baksidan någon millimeter åt sidan. Så här rättar du det:

1. Skriv ut bara det sista A4-arket (sidorna 5–6 i PDF-filen), dubbelsidigt, 100 %.
2. Håll arket mot ljuset. Läs av siffran på skalan där baksidans linje hamnar: plus åt höger, minus åt vänster.
3. Ange värdet i `BACK_OFFSET_MM` överst i `dokument/verktyg/make_booklet.py` och kör `python dokument/verktyg/make_docs.py`. Baksidorna flyttas då lika långt åt andra hållet.

PDF-filen görs om med `python dokument/verktyg/make_docs.py`; häftet görs samtidigt av `make_booklet.py`.
