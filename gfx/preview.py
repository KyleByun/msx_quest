"""Render what the MSX will actually display, straight from src/gfxdata.asm.

This reads back the generated data rather than the source PNGs, so it catches
mistakes in the conversion itself: a wrong sprite layer split, a bad tile
byte order, a map index off by one. Writes gfx/preview.png.
"""
from PIL import Image
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASM = os.path.join(ROOT, "src", "gfxdata.asm")


def load_asm():
    text = open(ASM).read() + open(os.path.join(ROOT, "src", "gfxconst.asm")).read()
    consts = {k: int(v) for k, v in re.findall(r"^(\w+)\s+equ\s+(\d+)", text, re.M)}
    consts["_names"] = {int(v): k for k, v in re.findall(r"^PAT_(\w+)\s+equ\s+(\d+)", text, re.M)}
    blocks, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"^(\w+):", line)
        if m:
            cur = m.group(1)
            blocks[cur] = []
            continue
        m = re.match(r"^\s+db\s+(.*)", line)
        if m and cur:
            blocks[cur] += [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", m.group(1))]
    return consts, blocks


def rgb(entry):
    r, b, g = (entry[0] >> 4) & 7, entry[0] & 7, entry[1] & 7
    return tuple(round(v * 255 / 7) for v in (r, g, b))


def main():
    consts, b = load_asm()
    pal = [rgb(b["PaletteData"][i * 2:i * 2 + 2]) for i in range(16)]
    ntiles, rows, cols = consts["TILE_COUNT"], consts["MAP_ROWS"], consts["MAP_COLS"]
    tiles, tmap = b["TileData"], b["TileMap"]
    pats, cols_tab = b["SpritePatterns"], b["SpriteColours"]
    npat = consts["SPR_PAT_COUNT"]

    def draw_tile(dst, t, ox, oy):
        for y in range(16):
            for x in range(0, 16, 2):
                byte = tiles[t * 128 + y * 8 + x // 2]
                dst[ox + x, oy + y] = pal[byte >> 4]
                dst[ox + x + 1, oy + y] = pal[byte & 15]

    # ---- the map as the MSX will render it ----
    scene = Image.new("RGB", (cols * 16, rows * 16))
    sp = scene.load()
    for r in range(rows):
        for c in range(cols):
            draw_tile(sp, tmap[r * cols + c], c * 16, r * 16)

    # ---- sprite planes, and the composite of each adjacent pair ----
    def plane(i):
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        p = img.load()
        for y in range(16):
            col = cols_tab[i * 16 + y] & 15
            if not col:
                continue
            left, right = pats[i * 32 + y], pats[i * 32 + 16 + y]
            bits = (left << 8) | right
            for x in range(16):
                if bits & (0x8000 >> x):
                    p[x, y] = pal[col] + (255,)
        return img

    planes = [plane(i) for i in range(npat)]

    S = 6
    sheet = Image.new("RGB", (npat * (16 * S + 4) + 4, 16 * S * 2 + 20), (30, 30, 30))
    for i, pl in enumerate(planes):
        sheet.paste(pl.resize((16 * S, 16 * S), Image.NEAREST), (4 + i * (16 * S + 4), 4), pl.resize((16 * S, 16 * S), Image.NEAREST))
    # Composite only the real two-plane sprites: a pattern named *_A followed
    # by its *_B partner. Single-plane sprites are shown as-is.
    names = consts["_names"]
    for i in range(npat):
        n = names.get(i, "")
        if n.endswith("_B"):
            continue
        comp = planes[i].copy()
        if n.endswith("_A") and names.get(i + 1, "") == n[:-2] + "_B":
            comp = Image.alpha_composite(comp, planes[i + 1])
        big = comp.resize((16 * S, 16 * S), Image.NEAREST)
        sheet.paste(big, (4 + i * (16 * S + 4), 16 * S + 12), big)

    out = Image.new("RGB", (max(scene.width, sheet.width), scene.height + sheet.height + 8), (30, 30, 30))
    out.paste(scene, (0, 0))
    out.paste(sheet, (0, scene.height + 8))
    out.save(os.path.join(HERE, "preview.png"))
    print(f"wrote gfx/preview.png  (map {cols}x{rows} tiles, {npat} sprite planes)")
    print("palette:", " ".join(f"{i}:{pal[i]}" for i in range(16)))


if __name__ == "__main__":
    main()
