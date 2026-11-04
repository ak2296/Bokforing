"""Draws the app icon into android_icon/res using only the Python standard
library. The GitHub build copies that folder into the Android project.

To change the icon, edit SHAPES and run: python tool/make_icon.py
"""
import os
import struct
import zlib

WHITE = (255, 255, 255)
DARK = (0x08, 0x4A, 0x37)
GREEN = (0x0B, 0x6B, 0x4F)
LIGHT = (0x1F, 0x9D, 0x75)


def rect(x1, y1, x2, y2):
    return [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]


# In a 108 x 108 square, painted in order: scan corners, folded page, bars.
SHAPES = [
    (DARK, rect(13, 13, 19, 30)), (DARK, rect(13, 13, 30, 19)),
    (DARK, rect(89, 13, 95, 30)), (DARK, rect(78, 13, 95, 19)),
    (DARK, rect(89, 78, 95, 95)), (DARK, rect(78, 89, 95, 95)),
    (DARK, rect(13, 78, 19, 95)), (DARK, rect(13, 89, 30, 95)),
    (GREEN, [(32, 26), (54, 26), (54, 82), (32, 82)]),
    (LIGHT, [(54, 26), (62, 26), (76, 40), (76, 82), (54, 82)]),
    (DARK, [(62, 26), (62, 40), (76, 40)]),
    (WHITE, rect(40, 62, 47, 74)),
    (WHITE, rect(50.5, 54, 57.5, 74)),
    (WHITE, rect(61, 46, 68, 74)),
]

SAMPLES = 4


def fill(grid, n, points, color, scale, offset):
    pts = [(x * scale + offset, y * scale + offset) for x, y in points]
    for row in range(n):
        y = row + 0.5
        cuts = []
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if (y1 <= y) != (y2 <= y):
                cuts.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
        cuts.sort()
        for a, b in zip(cuts[::2], cuts[1::2]):
            for col in range(max(0, round(a)), min(n, round(b))):
                grid[row][col] = color


def draw(size, art=1.0, background=True, radius=0.0):
    """Returns RGBA rows. [art] shrinks the artwork around the centre."""
    n = size * SAMPLES
    grid = [[None] * n for _ in range(n)]
    if background:
        r = radius * n / 108
        for row in range(n):
            for col in range(n):
                dx = max(r - col - 0.5, col + 0.5 - (n - r), 0)
                dy = max(r - row - 0.5, row + 0.5 - (n - r), 0)
                if dx * dx + dy * dy <= r * r:
                    grid[row][col] = WHITE
    scale = art * n / 108
    offset = n * (1 - art) / 2
    for color, points in SHAPES:
        fill(grid, n, points, color, scale, offset)
    out = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = a = 0
            for yy in range(y * SAMPLES, (y + 1) * SAMPLES):
                for xx in range(x * SAMPLES, (x + 1) * SAMPLES):
                    c = grid[yy][xx]
                    if c is not None:
                        r += c[0]
                        g += c[1]
                        b += c[2]
                        a += 1
            if a:
                row += bytes((r // a, g // a, b // a, a * 255 // (SAMPLES * SAMPLES)))
            else:
                row += bytes(4)
        out.append(bytes(row))
    return out


def write_png(path, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    size = len(rows)
    raw = b''.join(b'\0' + r for r in rows)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


RES = 'android_icon/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

for name, factor in DENSITIES.items():
    # Older phones: the whole icon, rounded.
    write_png(f'{RES}/mipmap-{name}/ic_launcher.png', draw(int(48 * factor), radius=24))
    # Newer phones cut the icon to their own shape, so the artwork must fit
    # inside the central circle of 66 out of 108.
    write_png(f'{RES}/mipmap-{name}/ic_launcher_foreground.png', draw(int(108 * factor), art=0.72, background=False))

write_text(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""")
write_text(f'{RES}/values/ic_launcher_background.xml', """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
""")
