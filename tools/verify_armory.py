"""Validate the self-contained snapshot without requiring the source repository."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "resources/create_armory"
manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
for original, expected in manifest["files"].items():
    if original.startswith("src/main/resources/assets/createarmory/"):
        target = ROOT / original.removeprefix("src/main/resources/assets/createarmory/")
    elif original.startswith("src/main/java/net/createarmory/"):
        target = ROOT / "provenance" / (original.removeprefix("src/main/java/net/createarmory/") + ".txt")
    else:
        target = ROOT / "provenance/mods.toml.txt"
    data = target.read_bytes()
    # Git normalizes text to LF; the pinned upstream snapshot used CRLF.
    hashes = {hashlib.sha256(data).hexdigest()}
    if target.suffix in {".txt", ".json", ".toml", ".mcmeta"}:
        hashes.add(hashlib.sha256(data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")).hexdigest())
    assert expected in hashes, original
assert hashlib.sha256((ROOT / "content.json").read_bytes()).hexdigest() == manifest["generated_content_sha256"]
content = json.loads((ROOT / "content.json").read_text())
source = (ROOT / "provenance/weapon/WeaponDefinition.java.txt").read_text()
registry = (ROOT / "provenance/init/CreatearmoryModItems.java.txt").read_text()
for gun in content["guns"]:
    assert re.search(r'register\("' + gun["id"] + r'", \(\) -> new GunItem\(WeaponDefinition\.' + gun["enum"] + r'\)', registry)
    match = re.search(r'^    ' + gun["enum"] + r'\((.*)\)[,;]', source, re.M)
    values = [value.strip().strip('"').removesuffix("f") for value in match[1].split(",")]
    for key, index in (("damage", 4), ("interval", 5), ("reload_ticks", 6), ("pellets", 8), ("speed", 9), ("spread", 10), ("recoil", 11), ("slots", 12)):
        assert gun[key] == float(values[index]), (gun["id"], key)
    assert gun["automatic"] == (values[7] == "true")
    geo = json.loads((ROOT / f"geo/{gun['model']}.geo.json").read_text())["minecraft:geometry"][0]
    clips = json.loads((ROOT / f"animations/{gun['model']}.animation.json").read_text())["animations"]
    assert {"idle", "fire", "reload", "equip", "reset"} <= clips.keys()
    assert abs(clips["reload"]["animation_length"] - gun["reload_ticks"] / 20) < 1e-7
    assert len({bone["name"] for bone in geo["bones"]}) == len(geo["bones"])
assert len(content["guns"]) == 12 and not content["armor"]
print(f"Verified {len(manifest['files'])} pinned files, 12 gun definitions, and no vanilla armor definitions.")
