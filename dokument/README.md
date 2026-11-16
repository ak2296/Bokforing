# Dokument

Användarguide, nedladdningskort och förpackning för appen Quee.

| Mapp | Innehåll |
|---|---|
| `anvandarguide/` | Användarguiden: HTML-källan `anvandarguide.html` (A5, 15 sidor; ur den görs de andra), telefonversionen `anvandarguide-telefon.pdf` (70 mm bred, samma som i appen) och tryckfilen för häftet i A6 med utfall: `anvandarguide-A6-tryckfil.pdf` |
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

## Till tryckeriet

Filerna är gjorda för att skickas som de är. Alla mått är verkliga (1:1). Färgerna är RGB (grön #0B6B4E, orange #E2600D och #F2832E); tryckeriet gör om dem till CMYK, be om ett korrektur (provtryck) på grönt och orange. Typsnitten (Inter, Poppins) är inbäddade i PDF-filerna.

| Fil | Vad | Mått |
|---|---|---|
| `anvandarguide/anvandarguide-A6-tryckfil.pdf` | Häftet, 36 sidor i läsordning (omslag, tom, innehåll, guiden, tom, baksida), en sida per PDF-sida. Tryckeriet lägger ut och häftar. | Färdigt A6 stående, 105 × 148,5 mm. Sidan är 111 × 154,5 mm: 3 mm utfall runt om. Bara omslaget har färg ut i kanten |
| `kort/kort.pdf` | Kortet, sida 1 framsida och sida 2 baksida | Färdigt 55 × 85 mm stående. Sidan är 61 × 91 mm: 3 mm utfall |
| `forpackning/forpackning-tryckfil.pdf` | Lådans tryck utan linjer: grönt med 3 mm utfall utanför skärlinjen, vitt på baksidan. Limfliken och insidan är otryckta | A4 liggande, 1:1. Lådan är 244 × 203 mm med flikar |
| `forpackning/forpackning-stans.pdf` | Stans- och biglinjerna ensamma, samma storlek och läge som tryckfilen. Röd heldragen = skär, blå streckad = vik | A4 liggande, 1:1 |

Lådan: tuck-box (vikbar ask med instick), innermått 109 × 152 × 7 mm, för ett A6-häfte med kortet ovanpå. Tryckeriet har oftast en egen stansmall för måttet; skicka då tryckfilen och be dem lägga konsten på sin mall (ytorna är: baksida 109 × 152, framsida 109 × 152, två kortsidor 7 × 152, lock 109 × 7 med instick). Förslag på papper: häfte 115 g insida och 250–300 g omslag, kort och låda 350 g kartong, matt. Fråga tryckeriet om vad de rekommenderar.
Lådans djup räknas om från häftets sidantal: `python dokument/verktyg/tjocklek.py [papperstjocklek_mm]` (A6-häftet är det som ligger i lådan). Djupet 7 mm räcker för ungefär 47-58 sidor beroende på papper; fråga tryckeriet om papper och häftning.

Omslaget på häftet har en telefonbild som går ut över högerkanten: den ska beskäras vid färdigt format, inte vid utfallet.

PDF-filerna görs om med `python dokument/verktyg/make_docs.py`.

