"""Grime decal textures for the MedTac Research Campus (RGBA PNG, standard
library only). Deterministic: the same textures are produced on every run."""
import ast
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/campus/decals'
SIZE = 128

tree = ast.parse((ROOT / 'tools/build_medtac_textures.py').read_text(encoding='utf-8'))
font_node = next(n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'FONT' for t in n.targets))
namespace = {}
exec(compile(ast.Module(body=[font_node], type_ignores=[]), '<font>', 'exec'), {'__builtins__': {}}, namespace)
FONT = namespace['FONT']


def h(x, y, seed):
    n = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xffffffff
    n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0


def noise(x, y, scale, seed):
    """Smooth value noise in [0, 1]."""
    gx, gy = x / scale, y / scale
    x0, y0 = int(math.floor(gx)), int(math.floor(gy))
    fx, fy = gx - x0, gy - y0
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = h(x0, y0, seed), h(x0 + 1, y0, seed)
    c, d = h(x0, y0 + 1, seed), h(x0 + 1, y0 + 1, seed)
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy


def fbm(x, y, seed):
    return noise(x, y, 32, seed) * .55 + noise(x, y, 12, seed + 1) * .3 + noise(x, y, 5, seed + 2) * .15


def radial(x, y):
    dx, dy = (x - SIZE / 2) / (SIZE / 2), (y - SIZE / 2) / (SIZE / 2)
    return math.sqrt(dx * dx + dy * dy)


def clamp(v):
    return max(0.0, min(1.0, v))


def write(name, pixel):
    rows = []
    for y in range(SIZE):
        row = bytearray(b'\0')
        for x in range(SIZE):
            r, g, b, a = pixel(x, y)
            row += bytes((int(clamp(r) * 255), int(clamp(g) * 255), int(clamp(b) * 255), int(clamp(a) * 255)))
        rows.append(bytes(row))

    def chunk(tag, data):
        return struct.pack('!I', len(data)) + tag + data + struct.pack('!I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', SIZE, SIZE, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
    (OUT / (name + '.png')).write_bytes(png)


def blob(seed, edge=.85):
    return lambda x, y: clamp((edge - radial(x, y) + (fbm(x, y, seed) - .5) * .7) * 3)


def text_mask(word, scale=3):
    width = len(word) * 6 * scale
    left, top = (SIZE - width) // 2, SIZE // 2 - 4 * scale
    cells = set()
    for col, ch in enumerate(word):
        for gy, bits in enumerate(FONT.get(ch, FONT[' '])):
            for gx, bit in enumerate(bits):
                if bit == '1':
                    for dy in range(scale):
                        for dx in range(scale):
                            cells.add((left + col * 6 * scale + gx * scale + dx, top + gy * scale + dy))
    return cells


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    stain = blob(11)
    write('water_stain', lambda x, y: (.36, .29, .19, stain(x, y) * (.35 + .45 * abs(math.sin(radial(x, y) * 14 + fbm(x, y, 3) * 4)))))
    mould = blob(21, .8)
    write('mould', lambda x, y: (.1, .16, .08, mould(x, y) * (.5 + .5 * (noise(x, y, 4, 22) > .45))))
    write('drips', lambda x, y: (.18, .17, .13, clamp(1 - y / SIZE * (.6 + h(x // 4, 0, 31) * .9)) * (.25 + .6 * (noise(x, 0, 3, 32) > .55)) * clamp(1 - abs(x - SIZE / 2) / (SIZE / 2))))
    soot = blob(41, .9)
    write('soot', lambda x, y: (.05, .05, .045, soot(x, y) * clamp(1.15 - y / SIZE * .5) * (.75 + .25 * fbm(x, y, 42))))
    grime = blob(51, .95)
    write('floor_grime', lambda x, y: (.24, .22, .17, grime(x, y) * (.35 + .4 * fbm(x, y, 52))))
    dust = blob(61, .95)
    write('dust', lambda x, y: (.72, .7, .62, dust(x, y) * .45 * (.6 + .4 * fbm(x, y, 62))))
    write('mud_tracks', lambda x, y: (.26, .2, .12, clamp(1 - abs(y - SIZE / 2 - math.sin(x * .05) * 10) / 22) * (.3 + .6 * fbm(x, y, 72)) * clamp(1 - abs(x - SIZE / 2) / (SIZE / 2) * .8)))
    blood = blob(81, .7)
    write('blood_smear', lambda x, y: (.24, .04, .03, blood(x, y) * (.55 + .45 * clamp(1 - abs(y - SIZE / 2 - (x - 64) * .3) / 30))))

    def boots(x, y):
        for i in range(6):
            cx, cy = 14 + i * 20, 46 + (18 if i % 2 else 0)
            dx, dy = (x - cx) / 6.0, (y - cy) / 11.0
            if dx * dx + dy * dy < 1 and (y - cy) % 4 != 0:
                return (.2, .16, .11, .6)
        return (0, 0, 0, 0)
    write('bootprints', boots)

    def cracks(x, y):
        value = 0.0
        for seed in range(4):
            line = abs(noise(x, y, 20, 90 + seed) - .5)
            if line < .012:
                value = .85
        missing = (x // 32 + y // 32 * 3) % 7 == 0 and noise(x, y, 6, 95) > .35
        return (.12, .12, .11, .8 if missing else value)
    write('tile_cracks', cracks)
    write('road_cracks', lambda x, y: (.08, .08, .08, .8 if abs(noise(x, y, 26, 101) - .5) < .014 or abs(noise(x, y, 18, 102) - .5) < .01 else 0))
    oil = blob(111, .75)
    write('oil_stain', lambda x, y: (.03, .03, .035, oil(x, y) * .75))
    pothole = blob(121, .6)
    write('pothole', lambda x, y: (.06, .06, .05, pothole(x, y) * .95))

    def tally(x, y):
        spray = noise(x, y, 2, 131) > .25
        for i in range(4):
            if abs(x - (30 + i * 16) - (y - 64) * .1) < 2.5 and 30 < y < 98:
                return (.55, .08, .06, .85 if spray else .4)
        if abs((y - 64) - (x - 64) * .55) < 2.5 and 18 < x < 108:
            return (.55, .08, .06, .85 if spray else .4)
        return (0, 0, 0, 0)
    write('graffiti_tally', tally)
    stripped = text_mask('STRIPPED')
    write('graffiti_stripped', lambda x, y: (.06, .06, .06, .9 if (x, y) in stripped and noise(x, y, 2, 141) > .2 else 0))
    print(f'CAMPUS DECALS: {len(list(OUT.glob("*.png")))} textures in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
