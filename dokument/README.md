# Dokument

Användarguide, nedladdningskort och förpackning för appen Quee.

| Mapp | Innehåll |
|---|---|
| `anvandarguide/` | Användarguiden, 15 sidor A5 (HTML-källa och PDF, samma som i appen) och två filer för utskrift som häfte: `anvandarguide-tryck-omslag.pdf` och `anvandarguide-tryck-inlaga.pdf` |
| `kort/` | Kort 55 × 85 mm (stående) med QR-kod, fram- och baksida |
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

Häftet är A5, tryckt på A4-papper med två sidor per arksida.

- **Omslag** (`anvandarguide/anvandarguide-tryck-omslag.pdf`): 1 ark, **enkelsidigt**. Baksidan (vit med liten logga och namn) och framsidan ligger bredvid varandra; insidan är vit.
- **Inlaga** (`anvandarguide/anvandarguide-tryck-inlaga.pdf`): 16 sidor på 4 ark, **dubbelsidigt**, vänd längs **kortsidan**. Första arket har innehållsförteckningen och sista sidan på ena sidan, sidan 3 och näst sista sidan på den andra, och så vidare. De två sista sidorna är "Anteckningar".

1. Skriv ut båda i **verklig storlek (100 %)**.
2. Lägg inlagans ark i ordning, med första arket ytterst, och lägg dem i omslaget.
3. Vik allt på mitten (de små strecken visar mitten) och häfta två gånger i vikningen.

PDF-filerna görs om med `python dokument/verktyg/make_docs.py`; häftet görs samtidigt av `make_booklet.py`.
