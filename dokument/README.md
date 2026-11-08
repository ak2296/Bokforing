# Dokument

Användarguide, nedladdningskort och förpackning för appen Quee.

| Mapp | Innehåll |
|---|---|
| `anvandarguide/` | Användarguiden, 15 sidor A5 (HTML-källa och PDF, samma som i appen) och `anvandarguide-tryck.pdf` för utskrift som häfte |
| `kort/` | Kort 85 × 55 mm med QR-kod, fram- och baksida |
| `forpackning/` | Tuck-box 154 × 216 × 14 mm: tryckfil med stans- och biglinjer (A3) och förhandsvisning |
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

`anvandarguide/anvandarguide-tryck.pdf` är ett A5-häfte på A4-papper: 16 sidor på 4 ark. Baksidan av omslaget är vit; övriga sidor är dubbelsidiga.

1. Skriv ut på A4, **dubbelsidigt**, **vänd längs kortsidan**, i **verklig storlek (100 %)**.
2. Lägg arken i ordning med omslaget ytterst, vik dem på mitten (de små strecken visar mitten).
3. Häfta två gånger i vikningen.

PDF-filerna görs om med `python dokument/verktyg/make_docs.py`; häftet görs samtidigt av `make_booklet.py`.
