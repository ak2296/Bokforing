# Dokument

Användarguide, nedladdningskort och förpackning för appen Bokföring.

| Mapp | Innehåll |
|---|---|
| `anvandarguide/` | Användarguiden, 15 sidor A5 (HTML-källa och PDF) |
| `kort/` | Kort 85 × 55 mm med QR-kod, fram- och baksida |
| `forpackning/` | Tuck-box 154 × 216 × 14 mm: tryckfil med stans- och biglinjer (A3) och förhandsvisning |
| `bilder/` | Appikon och QR-koden till nedladdningssidan |
| `forhandsvisning/` | Bilder av utvalda sidor |
| `verktyg/` | Skript som gör PDF-filerna och förhandsbilderna med Microsoft Edge |

Gör om PDF-filerna efter en ändring:

```bash
python dokument/verktyg/make_docs.py
```

QR-koden leder till https://ak2296.github.io/bokforing-app/, där den senaste versionen av appen kan laddas ner.

Ändringar i den här mappen startar inget nytt bygge av appen.
