#!/usr/bin/env python3
"""Build the local Dread Knight sheet from exported Thanatos body frames.

The source frames are produced by tools/build_dread_knight_frames.gd from the
player's own Ragnarok client. The output PNG lives in Resources/ (never
committed) and the generated frame map lives in the Godot project.

Run from the repository root:
    python tools/build_dread_knight_sheet.py
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "Resources" / "DreadKnight" / "raw" / "composed"
OUT_PNG = ROOT / "Resources" / "DreadKnight.png"
OUT_MAP = ROOT / "06_Godot_Project" / "data" / "sprites" / "dread_knight_sheet.json"

# Exact colour translation for the Thanatos palette.  Red cape/trim becomes
# indigo-violet; bone armour becomes cold charcoal-bone; blue hair becomes
# violet; the pale gem becomes an ember-red accent.
PALETTE = {
    (0x42, 0x00, 0x01): (0x0B, 0x0A, 0x1E),
    (0x6E, 0x25, 0x2D): (0x1A, 0x12, 0x33),
    (0x54, 0x36, 0x40): (0x2A, 0x1D, 0x45),
    (0x3B, 0x23, 0x31): (0x18, 0x13, 0x2E),
    (0x6D, 0x49, 0x4F): (0x33, 0x22, 0x4F),
    (0x8C, 0x35, 0x3E): (0x4A, 0x21, 0x68),
    (0xB2, 0x46, 0x51): (0x66, 0x30, 0x8A),
    (0xCB, 0x62, 0x66): (0x8A, 0x4B, 0xB3),
    (0x9E, 0x56, 0x52): (0x3A, 0x1A, 0x55),
    (0x82, 0x3F, 0x3B): (0x2B, 0x14, 0x40),
    (0x83, 0x5E, 0x5F): (0x2C, 0x24, 0x40),
    (0x82, 0x53, 0x53): (0x24, 0x1D, 0x36),
    (0x1A, 0x1A, 0x30): (0x14, 0x10, 0x1F),
    (0x29, 0x27, 0x3B): (0x1E, 0x18, 0x30),
    (0x47, 0x43, 0x59): (0x2E, 0x25, 0x45),
    (0x64, 0x5E, 0x77): (0x45, 0x37, 0x66),
    (0x7A, 0x6F, 0x8C): (0x5F, 0x4A, 0x85),
    (0x95, 0x8B, 0xA7): (0x7D, 0x64, 0xA6),
    (0xAF, 0xA7, 0xC1): (0xA5, 0x8B, 0xC9),
    (0xCE, 0xCC, 0xE0): (0xD8, 0xC8, 0xEE),
    (0xFF, 0xF3, 0xEB): (0xE8, 0xE2, 0xD0),
    (0xEE, 0xDF, 0xD7): (0xC9, 0xC1, 0xAE),
    (0xDC, 0xCB, 0xC3): (0xA9, 0xA3, 0x94),
    (0xB8, 0xA3, 0x9B): (0x8A, 0x85, 0x78),
    (0xA9, 0x8F, 0x8B): (0x6B, 0x68, 0x5F),
    (0x99, 0x72, 0x6F): (0x57, 0x54, 0x4F),
    (0x96, 0x6F, 0x66): (0x4A, 0x47, 0x44),
    (0xAF, 0x86, 0x7F): (0x6E, 0x6A, 0x60),
    (0xCA, 0xB7, 0xAF): (0x9C, 0x95, 0x87),
    (0xFF, 0xFF, 0xFF): (0xF5, 0xF1, 0xE6),
    (0xFF, 0xFF, 0xCB): (0xE0, 0x4A, 0x4A),
    (0xF4, 0x98, 0x92): (0xC8, 0xA6, 0xB2),
    (0xDC, 0x90, 0x84): (0xB0, 0x91, 0x9E),
    (0xA3, 0x87, 0x99): (0x8A, 0x74, 0x8C),
    (0xD6, 0xB8, 0xC7): (0xBD, 0xA9, 0xC6),
    (0xF0, 0xD1, 0xDC): (0xD8, 0xC6, 0xE0),
    (0x88, 0x6F, 0x82): (0x6A, 0x55, 0x70),
    (0x99, 0x7B, 0x7B): (0x6A, 0x66, 0x6A),
    (0x89, 0x67, 0x6B): (0x57, 0x4D, 0x5B),
}

# The source is a large monster. Scale its body to the height of a player
# body (the Lord Knight body frames peak at 85 px; Thanatos body frames peak
# at about 123 px).  2/3 keeps the pixel grid stable and lands around 82 px.
SCALE_NUM = 2
SCALE_DEN = 3

SELECTED = {
    0: [0],
    1: [0, 3, 6, 9, 12, 15],
    2: [0, 2, 4, 6],
    3: [0, 2, 4, 6],
    4: [12, 14, 16, 18, 20, 21],
}
CAST_FRAMES = [0, 2, 4, 6]
SHEET_MAX_WIDTH = 2048
GAP = 2
DARK = 70
SWORD_AREA = 1200
SWORD_WIDTH = 55


def remove_builtin_sword(img: Image.Image) -> None:
    """Remove the large near-black sword component from attack frames.

    Body outlines form many small dark components; the sword is a single
    component over 1,200 px wide.  Removing only that component leaves the
    body poses intact and lets the equipped weapon layer take its place.
    """
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    components: list[tuple[int, list[tuple[int, int]]]] = []

    for y in range(h):
        for x in range(w):
            if seen[y * w + x]:
                continue
            r, g, b, a = px[x, y]
            if a == 0 or max(r, g, b) >= DARK:
                continue
            queue = deque([(x, y)])
            seen[y * w + x] = 1
            cells: list[tuple[int, int]] = []
            while queue:
                cx, cy = queue.popleft()
                cells.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if not (0 <= nx < w and 0 <= ny < h) or seen[ny * w + nx]:
                        continue
                    rr, gg, bb, aa = px[nx, ny]
                    if aa > 0 and max(rr, gg, bb) < DARK:
                        seen[ny * w + nx] = 1
                        queue.append((nx, ny))
            components.append((len(cells), cells))

    for count, cells in components:
        if count < SWORD_AREA:
            continue
        xs = [c[0] for c in cells]
        if max(xs) - min(xs) <= SWORD_WIDTH:
            continue
        for x, y in cells:
            r, g, b, _a = px[x, y]
            px[x, y] = (r, g, b, 0)


def recolour(img: Image.Image) -> None:
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (*PALETTE.get((r, g, b), (r, g, b)), a)


def prepare(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    remove_builtin_sword(img)
    bbox = img.getbbox()
    if bbox is None:
        raise RuntimeError(f"{path.name} has no opaque pixels")
    img = img.crop(bbox)
    recolour(img)
    img = img.resize(
        (max(1, round(img.width * SCALE_NUM / SCALE_DEN)),
         max(1, round(img.height * SCALE_NUM / SCALE_DEN))),
        Image.Resampling.NEAREST,
    )
    return img


def pack(images: dict[str, Image.Image]) -> tuple[Image.Image, dict[str, list[int]]]:
    order = sorted(images, key=lambda key: (-images[key].height, key))
    rects: dict[str, list[int]] = {}
    x = y = 0
    row_h = 0
    used_w = 0
    for key in order:
        img = images[key]
        if x and x + img.width + GAP > SHEET_MAX_WIDTH:
            x = 0
            y += row_h + GAP
            row_h = 0
        rects[key] = [x, y, img.width, img.height]
        x += img.width + GAP
        row_h = max(row_h, img.height)
        used_w = max(used_w, x)
    sheet = Image.new("RGBA", (max(1, used_w), max(1, y + row_h)), (0, 0, 0, 0))
    for key, rect in rects.items():
        sheet.alpha_composite(images[key], (rect[0], rect[1]))
    return sheet, rects


def frame_id(action: int, frame: int) -> str:
    return f"a{action:02d}_f{frame:02d}"


def main() -> None:
    images: dict[str, Image.Image] = {}
    for base, frames in SELECTED.items():
        for direction in range(8):
            action = base * 8 + direction
            for frame in frames:
                path = RAW / f"a{action:02d}_f{frame:02d}.png"
                if not path.exists():
                    raise FileNotFoundError(f"missing exported frame {path}")
                images[frame_id(action, frame)] = prepare(path)

    sheet, rects = pack(images)
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_PNG, optimize=True)

    def dirs(base: int, frames: list[int]) -> dict[str, list[str]]:
        return {
            str(direction): [frame_id(base * 8 + direction, frame) for frame in frames]
            for direction in range(8)
        }

    idle = dirs(0, [0])
    walk = dirs(1, SELECTED[1])
    attack = dirs(2, SELECTED[2])
    hurt = dirs(3, SELECTED[3])
    dead = dirs(4, SELECTED[4])
    cast = dirs(2, CAST_FRAMES)
    groups = {
        "0": {"name": "idle", "interval": 200, "dirs": idle},
        "1": {"name": "walk", "interval": 150, "dirs": walk},
        "2": {"name": "sit", "interval": 200, "dirs": idle},
        "3": {"name": "pickup", "interval": 200, "dirs": idle},
        "4": {"name": "ready", "interval": 200, "dirs": idle},
        "5": {"name": "attack", "interval": 80, "dirs": attack},
        "6": {"name": "hurt", "interval": 75, "dirs": hurt},
        "7": {"name": "freeze", "interval": 200, "dirs": idle},
        "8": {"name": "dead", "interval": 100, "dirs": dead},
        "9": {"name": "unused", "interval": 200, "dirs": idle},
        "10": {"name": "unused", "interval": 200, "dirs": idle},
        "11": {"name": "unused", "interval": 200, "dirs": idle},
        "12": {"name": "cast", "interval": 100, "dirs": cast},
    }

    frame_map = {
        "_doc": (
            "Generated Dread Knight sheet from the player's own Thanatos client sprite. "
            "The image is kept locally as Resources/DreadKnight.png and is not redistributed. "
            "Body frames omit the built-in sword; the equipped Knight weapon layer is drawn "
            "over them. has_head is false because the sheet carries its own armoured head."
        ),
        "transparent": True,
        "has_head": False,
        "weapon_layer": True,
        "bg_sample": [2, 2],
        "key_tolerance": 54,
        "neck_from_top": 0,
        "frames": rects,
        "groups": groups,
        "front_dirs": [0, 1, 2, 6, 7],
        "back_dirs": [3, 4, 5],
    }
    OUT_MAP.write_text(json.dumps(frame_map, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUT_PNG} ({sheet.width}x{sheet.height}, {len(rects)} frames)")
    print(f"wrote {OUT_MAP}")


if __name__ == "__main__":
    main()
