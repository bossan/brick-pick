#!/usr/bin/env python3
"""Builds the bundled colour and set tables from Rebrickable's public catalogue dumps.

Usage: python3 Scripts/build_set_data.py [--cache DIR]

Writes BrickPick/Resources/colors.tsv (Rebrickable colour id, name, hex) and sets.tsv
(number, name, year, comma-separated "colour:bricks" pairs, where colour is a Rebrickable
colour id and bricks is how many parts of the set have that colour, spares excluded).
Transparent colours are dropped because the camera cannot read them.

Re-run to pick up newly released sets, then rebuild the app.
"""
import argparse
import collections
import csv
import gzip
import io
import pathlib
import tempfile
import urllib.request

BASE_URL = "https://cdn.rebrickable.com/media/downloads/"
TABLES = ["colors", "sets", "inventories", "inventory_parts", "inventory_minifigs"]
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "BrickPick" / "Resources"


def rows(directory, table):
    path = directory / f"{table}.csv.gz"
    if not path.exists():
        print(f"Downloading {table}…")
        urllib.request.urlretrieve(f"{BASE_URL}{table}.csv.gz", path)
    with gzip.open(path, "rt", encoding="utf-8", newline="") as file:
        yield from csv.DictReader(file)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cache", type=pathlib.Path, help="directory holding (or receiving) the downloaded dumps")
    args = parser.parse_args()
    directory = args.cache or pathlib.Path(tempfile.mkdtemp())
    directory.mkdir(parents=True, exist_ok=True)

    # Solid colours only; negative and 9999 ids are placeholders such as [Unknown].
    colors = [c for c in rows(directory, "colors") if c["is_trans"] == "False" and 0 <= int(c["id"]) < 9999]
    color_id = {c["id"]: int(c["id"]) for c in colors}

    # A set or minifig can have several inventory versions; the lowest is the original release.
    inventory_of = {}
    for inventory in rows(directory, "inventories"):
        current = inventory_of.get(inventory["set_num"])
        if current is None or int(inventory["version"]) < current[0]:
            inventory_of[inventory["set_num"]] = (int(inventory["version"]), inventory["id"])
    wanted = {inventory_id for _, inventory_id in inventory_of.values()}

    # Bricks per colour for every inventory.
    bricks_in = collections.defaultdict(collections.Counter)
    for part in rows(directory, "inventory_parts"):
        if part["inventory_id"] in wanted and part["color_id"] in color_id and part["is_spare"] == "False":
            bricks_in[part["inventory_id"]][color_id[part["color_id"]]] += int(part["quantity"])

    # Minifigs have inventories of their own; fold their parts into the sets that contain them.
    for minifig in rows(directory, "inventory_minifigs"):
        if minifig["inventory_id"] in wanted and minifig["fig_num"] in inventory_of:
            figure = bricks_in.get(inventory_of[minifig["fig_num"]][1], {})
            for color, quantity in figure.items():
                bricks_in[minifig["inventory_id"]][color] += quantity * int(minifig["quantity"])

    sets = []
    for lego_set in rows(directory, "sets"):
        inventory = inventory_of.get(lego_set["set_num"])
        bricks = sorted(bricks_in.get(inventory[1], {}).items()) if inventory else []
        if bricks:
            name = " ".join(lego_set["name"].split())
            sets.append((int(lego_set["year"]), lego_set["set_num"], name, bricks))
    sets.sort(key=lambda s: (-s[0], s[1]))

    OUTPUT.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT / "colors.tsv", "w", encoding="utf-8") as file:
        for color in colors:
            file.write(f"{color['id']}\t{color['name']}\t{color['rgb']}\n")
    with open(OUTPUT / "sets.tsv", "w", encoding="utf-8") as file:
        for year, number, name, bricks in sets:
            pairs = ",".join(f"{color}:{quantity}" for color, quantity in bricks)
            file.write(f"{number}\t{name}\t{year}\t{pairs}\n")
    print(f"Wrote {len(colors)} colours and {len(sets)} sets to {OUTPUT}")


if __name__ == "__main__":
    main()
