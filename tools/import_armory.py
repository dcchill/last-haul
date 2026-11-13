"""Snapshot the local mod without building or modifying it. Python 3.10+, stdlib only.

Run again with --check to verify both provenance and deterministic generated output.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = Path(r"C:\Users\daria\Documents\GitHub\Create-Armory")
PREFIX = "res://resources/create_armory/"
FEEDS = {"STANAG": (30, "five_five_six", "stanag_magazine"), "MAC": (30, "nine_mm", "mac_magazine"),
         "BARRET": (5, "fifty_cal", "barret_magazine"), "DRUM": (100, "nine_mm", "minigun_drum"),
         "DIRECT": (1, "nine_mm", ""), "SHELL": (2, "shotgun_shell", ""), "ROCKET": (1, "rpg_rocket", "")}


def collect(source):
    assets = source / "src/main/resources/assets/createarmory"
    java = source / "src/main/java/net/createarmory"
    definitions = (java / "weapon/WeaponDefinition.java").read_text(encoding="utf-8")
    registry = (java / "init/CreatearmoryModItems.java").read_text(encoding="utf-8")
    ids = {enum: item for item, enum in re.findall(r'register\("([^"]+)", \(\) -> new GunItem\(WeaponDefinition\.(\w+)\)', registry)}
    lang = json.loads((assets / "lang/en_us.json").read_text(encoding="utf-8"))
    guns = []
    for enum, args in re.findall(r'^    (\w+)\(("[^\n]+)\)[,;]', definitions, re.M):
        values = [v.strip().strip('"') for v in args.split(",")]
        model, texture, feed = values[:3]
        feed = feed.removeprefix("Feed.")
        capacity, ammo, magazine = FEEDS[feed]
        number = lambda i: float(values[i].removesuffix("f"))
        item = ids[enum]
        guns.append(dict(id=item, enum=enum, name=lang.get("item.createarmory." + item, item.replace("_", " ").title()),
                         model=model, texture=texture, feed=feed, capacity=capacity, ammo=ammo, magazine=magazine,
                         damage=number(4), interval=int(values[5]), reload_ticks=int(values[6]),
                         automatic=values[7] == "true", pellets=int(values[8]), speed=number(9),
                         spread=number(10), recoil=number(11), slots=int(values[12]),
                         head_multiplier=2.0 if feed == "BARRET" else 1.5,
                         can_aim=enum not in ("MINIGUN", "UPGRADED_MINIGUN")))
    assert len(guns) == 12, "Source registry changed: expected 12 registered guns"
    output = {}
    hashes = {}
    for file in sorted(assets.rglob("*")):
        if file.is_file():
            rel = file.relative_to(assets).as_posix()
            data = file.read_bytes()
            if file.suffix == ".json":
                json.loads(data)
            output["resources/create_armory/" + rel] = data
            hashes[file.relative_to(source).as_posix()] = hashlib.sha256(data).hexdigest()
    # Pin gameplay code alongside assets, including the dirty working tree, for audits.
    for folder in ("weapon", "entity", "procedures", "client/weapon", "init", "menu", "item", "block"):
        for file in sorted((java / folder).rglob("*.java")):
            rel = file.relative_to(java).as_posix()
            data = file.read_bytes()
            output["resources/create_armory/provenance/" + rel + ".txt"] = data
            hashes[file.relative_to(source).as_posix()] = hashlib.sha256(data).hexdigest()
    metadata = (source / "src/main/resources/META-INF/mods.toml").read_bytes()
    output["resources/create_armory/provenance/mods.toml.txt"] = metadata
    hashes["src/main/resources/META-INF/mods.toml"] = hashlib.sha256(metadata).hexdigest()
    for gun in guns:
        for path in (f"geo/{gun['model']}.geo.json", f"animations/{gun['model']}.animation.json", f"textures/item/{gun['texture']}.png"):
            assert (assets / path).is_file(), path
        clips = json.loads((assets / f"animations/{gun['model']}.animation.json").read_text())["animations"]
        assert abs(clips["reload"]["animation_length"] - gun["reload_ticks"] / 20) < 1e-6
    attachments = [dict(id=item, slot=slot.lower(), magnification=int(mag)) for item, slot, mag in
                   re.findall(r'register\("([^"]+)", \(\) -> new AttachmentItem\(AttachmentItem.Slot\.(\w+), (\d+)\)', registry)]
    # The supplied mod registers no functional armor; do not invent vanilla items.
    armors = []
    content = dict(version=1, tick_rate=20, guns=guns, attachments=attachments, armor=armors,
                   feeds={k: dict(capacity=v[0], ammo=v[1], magazine=v[2]) for k, v in FEEDS.items()},
                   previews=[p.stem.removesuffix(".geo") for p in sorted((assets / "geo").glob("*.json"))])
    output["resources/create_armory/content.json"] = (json.dumps(content, indent=2) + "\n").encode()
    manifest = dict(format=1, mod="Create Armory 0.6.0-dev", minecraft="1.20.1", license="Academic Free License v3.0",
                    files=hashes, generated_content_sha256=hashlib.sha256(output["resources/create_armory/content.json"]).hexdigest(),
                    mappings={g["id"]: {k: g[k] for k in ("model", "texture", "feed")} for g in guns})
    output["resources/create_armory/manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=DEFAULT)
    parser.add_argument("--check", action="store_true", help="Read-only verification; exits nonzero on drift")
    args = parser.parse_args()
    output = collect(args.source.resolve())
    changed = []
    for rel, data in output.items():
        target = ROOT / rel
        if not target.is_file() or target.read_bytes() != data:
            changed.append(rel)
            if not args.check:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
    print(f"{'Verified' if args.check else 'Imported'} {len(output)} files, 12 guns; {len(changed)} {'differences' if args.check else 'updated'}.")
    if args.check and changed:
        print("\n".join(changed))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
