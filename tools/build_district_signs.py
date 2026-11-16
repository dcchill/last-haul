"""Physical signs using the project's original bitmap alphabet. No dependencies."""
import ast
import re
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
tree = ast.parse((ROOT / 'tools/build_medtac_textures.py').read_text(encoding='utf-8'))
font_node = next(n for n in tree.body if isinstance(n, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == 'FONT' for t in n.targets))
namespace = {}
exec(compile(ast.Module(body=[font_node], type_ignores=[]), '<local bitmap font>', 'exec'),
     {'__builtins__': {}}, namespace)
FONT = namespace['FONT']
SIGNS = {
    'research': 'MEDTAC RESEARCH\nDIAGNOSTICS / CONTAINMENT',
    'scrapyard': 'VEYRA RECLAMATION\nSALVAGE / MACHINE SHOP',
    'residential': 'WORKERS RESIDENCES\nEVACUATION SUSPENDED',
    'warehouse': 'DISTRICT LOGISTICS\nCOLD CHAIN / DISPATCH',
    'substation': 'POWER SUBSTATION\nDANGER / HIGH VOLTAGE',
    'rail': 'RAIL FREIGHT DEPOT\nLAST DEPARTURE CANCELLED',
    'checkpoint': 'QUARANTINE CONTROL\nNO CIVILIAN TRANSIT',
    'restricted': 'RESTRICTED RESEARCH\nSINGLE USE CREDENTIAL',
    'evacuation': 'EVACUATION ASSEMBLY\nNO TRANSPORT AVAILABLE',
    'medical': 'MEDTAC / TRIAGE\nSUPPRESSANTS ARE NOT A CURE',
    'north': 'NORTH SERVICE GATE\nEXTRACTION / 15 SECONDS',
    'east': 'EAST FREIGHT GATE\nEXTRACTION / 15 SECONDS',
    'south': 'SOUTH EVACUATION\nEXTRACTION / 15 SECONDS',
    'west': 'WEST DRAINAGE EXIT\nEXTRACTION / 15 SECONDS',
    'campus_cure_transfer': 'CURE STOCK EVACUATED\nSUPPRESSANTS ARE NOT A CURE',
    'campus_trial_notice': 'TRIAL 19 / CONTAINMENT FAILED\nEXCLUSIVE CURE DISTRIBUTION',
}

def chunk(tag, data):
    return struct.pack('!I', len(data)) + tag + data + struct.pack('!I', zlib.crc32(tag + data) & 0xffffffff)

def main():
    # Campus room labels share the original physical bitmap-sign pipeline.
    author = (ROOT / 'tools/campus_scene_author.gd').read_text(encoding='utf-8')
    roles = 'analysis|microscopy|preparation|sterile|cold|clinical|recovery|isolation|toilet|office|control|records|meeting|staff|receiving|packing|utility|generator|pump|electrical|workshop|decon|containment|waiting|security|medical|store'
    titles = re.findall(r'\["([^"]+)","(?:' + roles + r')"\]', author)
    titles += re.findall(r'room\([^,]+,"([^"]+)"', author)
    for title in titles:
        identity = 'campus_' + title.lower().replace('/', '_').replace(' ', '_')
        # Wrap long room names at word boundaries instead of clipping lettering.
        words, lines = title.upper().split(), ['']
        for word in words:
            if len(lines[-1]) + len(word) + 1 > 38:
                lines.append('')
            lines[-1] = (lines[-1] + ' ' + word).strip()
        SIGNS[identity] = '\n'.join(lines)
    directory = ROOT / 'assets/district/signs'
    directory.mkdir(parents=True, exist_ok=True)
    for identity, text in SIGNS.items():
        w, h, scale = 512, 96, 2
        pixels = bytearray([38, 53, 49] * w * h)
        lines = text.splitlines()
        for row, line in enumerate(lines):
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
                                    pixels[at:at+3] = bytes((202, 207, 180))
        for x in range(5, w-5):
            for y in (5, 6, h-6, h-7):
                pixels[(y*w+x)*3:(y*w+x)*3+3] = bytes((150, 157, 130))
        data = b''.join(b'\0' + pixels[y*w*3:(y+1)*w*3] for y in range(h))
        (directory / (identity + '.png')).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', w,h,8,2,0,0,0)) + chunk(b'IDAT', zlib.compress(data,9)) + chunk(b'IEND', b''))
    print(f'DISTRICT SIGNS: {len(SIGNS)} original physical sign textures')

if __name__ == '__main__':
    main()
