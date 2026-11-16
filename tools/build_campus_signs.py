"""Printed signs for the MedTac Research Campus, using the project's original
bitmap alphabet (tools/build_medtac_textures.py). Python standard library only.

Room plates are read from tools/campus/*_plan.gd; generated room series
(patient, examination and trial treatment rooms) are listed explicitly."""
import ast
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
tree = ast.parse((ROOT / 'tools/build_medtac_textures.py').read_text(encoding='utf-8'))
font_node = next(n for n in tree.body if isinstance(n, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == 'FONT' for t in n.targets))
namespace = {}
exec(compile(ast.Module(body=[font_node], type_ignores=[]), '<local bitmap font>', 'exec'),
     {'__builtins__': {}}, namespace)
FONT = namespace['FONT']

STORY = {
    'medtac_poster_tomorrow': 'MEDTAC BIOMEDICAL\nMAKING TOMORROW TREATABLE',
    'medtac_poster_care': 'ADVANCED CARE\nACCESSIBLE TO EVERYONE',
    'evacuation_notice': 'EVACUATION SUSPENDED\nREMAIN AT YOUR STATION',
    'lockdown_notice': 'CONTAINMENT LOCKDOWN\nAUTHORISED STAFF ONLY',
    'dont_go_up': 'DONT GO UP\nTHEY ARE ON FOUR',
    'mt_rg_01': 'MT-RG/01 REGENESIS\nRESTRICTED PROGRAMME',
    'exposure_trial': 'CONTROLLED EXPOSURE TRIAL\nAPPROVED BY EXECUTIVE BOARD',
    'regenesis_board': 'REGENESIS / TRANSFER RATE\nHOST TO HOST CONFIRMED',
    'containment_failed': 'CONTAINMENT FAILED\nSEAL THIS FLOOR',
    'do_not_open': 'DO NOT OPEN\nINFECTED INSIDE',
    'destroy_records': 'SHRED EVERYTHING\nBY ORDER OF LEGAL',
    'triage_full': 'TRIAGE FULL\nNO FURTHER ADMISSIONS',
    'quarantine_ward': 'QUARANTINE WARD\nMASKS AT ALL TIMES',
    'skybridge': 'SKYBRIDGE\nTO CLINICAL BUILDING',
    'skybridge_research': 'SKYBRIDGE\nTO RESEARCH BUILDING',
    'distribution_sign': 'MEDTAC DISTRIBUTION\nRECEIVING DOCKS 1-6',
    'restricted': 'RESTRICTED RESEARCH\nSINGLE USE CREDENTIAL',
    'evacuation': 'EVACUATION ASSEMBLY\nNO TRANSPORT AVAILABLE',
    'checkpoint': 'QUARANTINE CONTROL\nNO CIVILIAN TRANSIT',
    'extract_north': 'NORTH ROAD\nEXTRACTION / 15 SECONDS',
    'extract_east': 'EAST ROAD\nEXTRACTION / 15 SECONDS',
    'extract_south': 'SOUTH ROAD\nEXTRACTION / 15 SECONDS',
    'extract_west': 'WEST CHECKPOINT\nEXTRACTION / 15 SECONDS',
}
LEVELS = {
    'lab1': ['RECEPTION AND ADMINISTRATION', 'PHARMACEUTICAL RESEARCH', 'RESTRICTED RESEARCH / SKYBRIDGE', 'ADVANCED RESEARCH / EXECUTIVE'],
    'lab2': ['INTAKE AND EMERGENCY', 'PATIENT CARE AND OBSERVATION', 'CLINICAL TRIALS / SKYBRIDGE', 'INTENSIVE CARE / EXPERIMENTAL'],
    'distribution_wing': ['DISPATCH AND STAFF', 'OFFICES AND SECURITY'],
}


def sign_id(title):
    return re.sub(r'[^a-z0-9]+', '_', title.lower()).strip('_')


def chunk(tag, data):
    return struct.pack('!I', len(data)) + tag + data + struct.pack('!I', zlib.crc32(tag + data) & 0xffffffff)


def wrap(title):
    words, lines = title.upper().replace("'", '').split(), ['']
    for word in words:
        if len(lines[-1]) + len(word) + 1 > 38:
            lines.append('')
        lines[-1] = (lines[-1] + ' ' + word).strip()
    return '\n'.join(lines)


def write(directory, identity, text, palette):
    w, h, scale = 512, 96, 2
    background, ink, rule = palette
    pixels = bytearray(bytes(background) * w * h)
    for row, line in enumerate(text.splitlines()[:2]):
        left = (w - len(line) * 6 * scale) // 2
        for col, char in enumerate(line):
            for gy, bits in enumerate(FONT.get(char, FONT[' '])):
                for gx, bit in enumerate(bits):
                    if bit != '1':
                        continue
                    for dy in range(scale):
                        for dx in range(scale):
                            x, y = left + col * 6 * scale + gx * scale + dx, 18 + row * 34 + gy * scale + dy
                            if 0 <= x < w and 0 <= y < h:
                                at = (y * w + x) * 3
                                pixels[at:at + 3] = bytes(ink)
    for x in range(5, w - 5):
        for y in (5, 6, h - 6, h - 7):
            pixels[(y * w + x) * 3:(y * w + x) * 3 + 3] = bytes(rule)
    data = b''.join(b'\0' + pixels[y * w * 3:(y + 1) * w * 3] for y in range(h))
    (directory / (identity + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(data, 9)) + chunk(b'IEND', b''))


def main():
    titles = []
    for plan in sorted((ROOT / 'tools/campus').glob('*_plan.gd')):
        titles += re.findall(r'R\("([^"]+)"', plan.read_text(encoding='utf-8'))
    titles += ['Patient room %d' % n for n in list(range(201, 211)) + list(range(211, 217))]
    titles += ['Examination room %d' % n for n in range(1, 6)]
    titles += ['Trial treatment room %d' % n for n in range(1, 4)]
    directory = ROOT / 'assets/campus/signs'
    directory.mkdir(parents=True, exist_ok=True)
    corporate = ((226, 230, 222), (38, 92, 92), (64, 140, 136))
    warning = ((52, 46, 36), (214, 186, 92), (150, 122, 60))
    count = 0
    for title in sorted(set(titles)):
        write(directory, sign_id(title), wrap(title), corporate)
        count += 1
    for identity, text in STORY.items():
        write(directory, identity, text, warning if identity not in ('medtac_poster_tomorrow', 'medtac_poster_care', 'skybridge', 'skybridge_research', 'distribution_sign') else corporate)
        count += 1
    for building, names in LEVELS.items():
        for index, name in enumerate(names):
            write(directory, 'level_%d_%s' % (index + 1, building), 'LEVEL %d\n%s' % (index + 1, name), corporate)
            count += 1
    print(f'CAMPUS SIGNS: {count} printed sign textures in {directory.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
