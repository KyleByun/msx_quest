"""Convert the Zanac reference PNGs into MSX2 SCREEN 5 graphics data.

Pipeline
    source PNG
      -> shared 16-colour palette in the V9938's RGB333 space
      -> dithered / colour-mapped PNG written back to images/ (for inspection)
      -> .asm data included by the game

Two different mappings are used on purpose:

  Sprites are mapped nearest-colour with NO error diffusion. They are 16x16
  pixel art; dithering a silhouette that small just scatters noise across it.

  Background tiles are dithered with an ordered 4x4 Bayer matrix. Ordered, not
  Floyd-Steinberg: error diffusion does not tile, so a scrolling map would show
  a seam at every tile boundary.

Run:  uv run --with pillow python gfx/convert.py
"""
from PIL import Image
from collections import Counter
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
IMAGES = os.path.join(ROOT, "images")
SRCOUT = os.path.join(ROOT, "src")

MSX_SHEET = os.path.join(IMAGES, "msx_zanac.png")
NES_SHEET = os.path.join(IMAGES, "nes_zanac.png")
FORTRESS = os.path.join(IMAGES, "zanac-fortresses.png")

MSX_BG = (0, 91, 91)            # backdrop colour of the MSX sprite sheet
NES_BG = (244, 120, 252)        # backdrop colour of the NES sprite sheet

# The fortress screenshots are a 2x2 grid of captures. The top-right one (black
# with a yellow grid) is the most tile-regular: 50 distinct 16x16 blocks out of
# 240. Its grid is offset by 1px, found by minimising the distinct-block count.
FORT_PHASE = (1, 1)
TILE_COUNT = 16                 # how many distinct tiles to keep

# Colours that appear in the fortress quadrant but belong to sprites or the
# HUD, not the background. Any candidate tile containing one is discarded.
FORT_BG_COLOURS = {(0, 0, 0), (136, 136, 0), (232, 208, 32), (160, 48, 0), (224, 80, 0)}

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------

def snap333(c):
    """Snap an 8-bit RGB triple to the V9938's 3-bits-per-channel space."""
    return tuple(round(v * 7 / 255) for v in c)


def rgb333_to_rgb888(c):
    return tuple(round(v * 255 / 7) for v in c)


def build_palette(pixel_pools, n=15, label="game"):
    """Build the one shared palette from every asset we actually use.

    SCREEN 5 has ONE 16-colour palette for the whole screen - sprites and
    background index the same table - so it must be built from both at once.
    Index 0 is reserved: it is transparent for sprites and the backdrop colour
    for the bitmap, so no artwork may use it.

    The sources are pixel art, so we keep their exact colours (snapped into the
    V9938's RGB333 space) rather than re-quantising. Only if that exceeds the
    budget do we reduce, by repeatedly merging the rarest colour into its
    nearest neighbour - which is where the background dithering earns its keep.
    """
    counts = Counter()
    for pool in pixel_pools:
        for c in pool:
            counts[snap333(c)] += 1

    pal = dict(counts)
    merged = 0
    while len(pal) > n:
        rarest = min(pal, key=lambda c: pal[c])
        rest = [c for c in pal if c != rarest]
        into = min(rest, key=lambda c: sum((c[i] - rarest[i]) ** 2 for i in range(3)))
        pal[into] += pal.pop(rarest)
        merged += 1

    ordered = [c for c, _ in sorted(pal.items(), key=lambda kv: -kv[1])]
    while len(ordered) < n:
        ordered.append((0, 0, 0))
    print(f"  {label} palette: {len(counts)} distinct RGB333 colours, "
          f"{merged} merged to fit {n} slots")
    return [(0, 0, 0)] + ordered         # index 0 = transparent/backdrop


def nearest(pal, rgb888, skip0=True):
    best, bi = None, 1
    start = 1 if skip0 else 0
    for i in range(start, len(pal)):
        p = rgb333_to_rgb888(pal[i])
        d = (p[0] - rgb888[0]) ** 2 + (p[1] - rgb888[1]) ** 2 + (p[2] - rgb888[2]) ** 2
        if best is None or d < best:
            best, bi = d, i
    return bi


def nearest_dithered(pal, rgb888, x, y, spread=28):
    t = (BAYER4[y % 4][x % 4] + 0.5) / 16.0 - 0.5
    biased = tuple(max(0, min(255, v + t * spread)) for v in rgb888)
    return nearest(pal, biased)


# --------------------------------------------------------------------------
# sprite extraction
# --------------------------------------------------------------------------

def crop16(im, box, bg, flip_v=False):
    """Lift exactly the component's bounding box into a blank 16x16 cell.

    Cropping a 16x16 window centred on the component instead would drag in
    whatever sits next to it on the sheet - the bullet bars are only 5px apart.
    """
    x, y, w, h = box
    src = im.crop((x, y, x + w, y + h))
    cell = Image.new("RGB", (16, 16), bg)
    cell.paste(src, ((16 - w) // 2, (16 - h) // 2))
    if flip_v:
        cell = cell.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return cell


def sprite_layers(cell, bg, pal, drop=()):
    """Split a 16x16 cell into two disjoint hardware-sprite layers.

    A mode 2 sprite has one colour per scanline, so a multicoloured ship needs
    more than one sprite plane. Each line is split into its two most common
    colours; any third colour on that line is folded into whichever of the two
    is nearer. The two layers never share a pixel, so they compose correctly
    under normal sprite priority and need no CC (OR) bit.
    """
    p = cell.load()
    idx = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            c = p[x, y]
            idx[y][x] = 0 if (c == bg or c in drop) else nearest(pal, c)

    maskA = [0] * 16
    maskB = [0] * 16
    colA = [0] * 16
    colB = [0] * 16
    for y in range(16):
        counts = Counter(v for v in idx[y] if v)
        if not counts:
            continue
        ranked = [c for c, _ in counts.most_common()]
        cA = ranked[0]
        cB = ranked[1] if len(ranked) > 1 else 0
        colA[y], colB[y] = cA, cB
        for x in range(16):
            v = idx[y][x]
            if not v:
                continue
            if v == cA:
                maskA[y] |= 0x8000 >> x
            elif v == cB:
                maskB[y] |= 0x8000 >> x
            else:
                ra = rgb333_to_rgb888(pal[cA])
                rb = rgb333_to_rgb888(pal[cB]) if cB else None
                rv = rgb333_to_rgb888(pal[v])
                da = sum((ra[i] - rv[i]) ** 2 for i in range(3))
                db = sum((rb[i] - rv[i]) ** 2 for i in range(3)) if rb else 1 << 30
                if da <= db:
                    maskA[y] |= 0x8000 >> x
                else:
                    maskB[y] |= 0x8000 >> x
    return (maskA, colA), (maskB, colB)


def pattern_bytes(mask):
    """MSX 16x16 pattern: 16 left-half bytes then 16 right-half bytes."""
    left = [(m >> 8) & 0xFF for m in mask]
    right = [m & 0xFF for m in mask]
    return left + right


# --------------------------------------------------------------------------
# HUD artwork - generated, not lifted from the sheets
# --------------------------------------------------------------------------

# 5x7 digits, one 5-bit value per row, bit 4 leftmost. Deliberately smaller
# than the 8x8 set the HUD used to carry - the readouts are dense now.
DIGIT_W = 5
DIGIT_FONT = [
    [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],  # 0
    [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],  # 1
    [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],  # 2
    [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],  # 3
    [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],  # 4
    [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],  # 5
    [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],  # 6
    [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],  # 7
    [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],  # 8
    [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],  # 9
]


# HUD labels, same 5x7 body as the digits: "F" for fps, "C" for cpu.
LABEL_FONT = [
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],  # F
    [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],  # C
]

# The GAME OVER message stays 8x8: it is a headline, not a readout.
LETTER_W = 8
LETTER_FONT = [
    [0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0x00],  # G
    [0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00],  # A
    [0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0x00],  # M
    [0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00],  # E
    [0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00],  # O
    [0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x00],  # V
    [0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00],  # R
]


def glyph_mask(rows, width):
    """A glyph placed at the top-left of a 16x16 sprite cell."""
    shift = 16 - width
    return [rows[y] << shift if y < len(rows) else 0 for y in range(16)]


def digit_mask(d):
    return glyph_mask(DIGIT_FONT[d], DIGIT_W)


def energy_mask(filled):
    """Energy gauge segment showing `filled` of 16 columns lit.

    Row 1 and row 8 are the full-width container, so an empty gauge still
    reads as a gauge rather than as nothing at all.
    """
    m = [0] * 16
    m[1] = 0xFFFF
    m[8] = 0xFFFF
    if filled:
        bits = ((1 << filled) - 1) << (16 - filled)
        for y in range(2, 8):
            m[y] = bits & 0xFFFF
    return m


def slice_cells(im, box, bg, cols, rows, flip_v=False):
    """Cut a large sprite into a cols x rows grid of 16x16 cells."""
    x, y, w, h = box
    src = im.crop((x, y, x + w, y + h))
    if flip_v:
        src = src.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    sheet = Image.new("RGB", (cols * 16, rows * 16), bg)
    sheet.paste(src, ((cols * 16 - w) // 2, (rows * 16 - h) // 2))
    return [sheet.crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16))
            for r in range(rows) for c in range(cols)]


# --------------------------------------------------------------------------
# tile extraction
# --------------------------------------------------------------------------

def extract_tiles():
    im = Image.open(FORTRESS).convert("RGB")
    W, H = im.size
    q = im.crop((W // 2, 0, W, H // 2))
    dx, dy = FORT_PHASE

    grid, seen = [], {}
    order = []
    for by in range(dy, q.height - 15, 16):
        row = []
        for bx in range(dx, q.width - 15, 16):
            t = q.crop((bx, by, bx + 16, by + 16))
            key = t.tobytes()
            if key not in seen:
                seen[key] = t
                order.append(key)
            row.append(key)
        grid.append(row)

    counts = Counter(k for row in grid for k in row)

    def clean(key):
        return set(seen[key].get_flattened_data()) <= FORT_BG_COLOURS

    clean_keys = [k for k, _ in counts.most_common() if clean(k)][:TILE_COUNT]
    dropped = len([k for k in order if not clean(k)])
    print(f"  tiles: {len(order)} distinct, {dropped} rejected as sprite/HUD "
          f"contamination, keeping {len(clean_keys)}")

    # Any map cell using a rejected tile is replaced by the nearest kept tile,
    # so the fortress layout stays coherent instead of punching holes in it.
    def nearest_clean(key):
        src = list(seen[key].get_flattened_data())
        best, bk = None, clean_keys[0]
        for ck in clean_keys:
            cand = list(seen[ck].get_flattened_data())
            d = sum((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2
                    for a, b in zip(src, cand))
            if best is None or d < best:
                best, bk = d, ck
        return bk

    remap = {}
    for k in order:
        remap[k] = clean_keys.index(k) if k in clean_keys else clean_keys.index(nearest_clean(k))

    tilemap = [[remap[k] for k in row] for row in grid]
    tiles = [seen[k] for k in clean_keys]
    return tiles, tilemap


# --------------------------------------------------------------------------
# emit
# --------------------------------------------------------------------------

def db(name, data, per_line=16):
    out = [f"{name}:"]
    for i in range(0, len(data), per_line):
        out.append("    db " + ", ".join(f"0x{v:02X}" for v in data[i:i + per_line]))
    return "\n".join(out)


def main():
    msx = Image.open(MSX_SHEET).convert("RGB")
    nes = Image.open(NES_SHEET).convert("RGB")

    # Source rectangles, as (x, y, w, h) on the sheet. These are the bounding
    # boxes of connected non-background runs, found by flood-filling the sheets.
    player_boxes = [(33, 0, 14, 15), (48, 0, 15, 15), (64, 0, 14, 15)]   # bank L / centre / bank R
    enemy_boxes = [(104, 6, 16, 16), (27, 7, 13, 14), (66, 8, 12, 12)]   # NES craft, orb, diamond
    pbullet_box = (12, 57, 4, 12)                                        # MSX sheet: thin bolt
    ebullet_box = (24, 131, 10, 10)                                      # MSX sheet: orange orb

    player_cells = [crop16(msx, b, MSX_BG) for b in player_boxes]
    # Flipped so the enemy craft face down the screen at the player.
    enemy_cells = [crop16(nes, b, NES_BG, flip_v=True) for b in enemy_boxes]
    pbullet_cell = crop16(msx, pbullet_box, MSX_BG)
    ebullet_cell = crop16(msx, ebullet_box, MSX_BG)

    # Bosses are single large craft cut into a grid of hardware sprites. The
    # grids are kept small on purpose: a boss borrows the enemy slots, so its
    # cell count is what forces MAX_EN, and every slot spent there is one the
    # HUD cannot have.
    mboss_grid = (2, 2)                 # cols, rows
    gboss_grid = (3, 3)
    mboss_cells = slice_cells(nes, (337, 81, 32, 32), NES_BG, *mboss_grid)
    gboss_cells = slice_cells(nes, (234, 77, 50, 38), NES_BG, *gboss_grid, flip_v=True)

    tiles, tilemap = extract_tiles()

    def used(im, bg):
        return [c for c in im.get_flattened_data() if c != bg]

    pools = [used(c, MSX_BG) for c in player_cells]
    pools += [used(c, NES_BG) for c in enemy_cells]
    pools += [used(pbullet_cell, MSX_BG), used(ebullet_cell, MSX_BG)]
    pools += [used(c, NES_BG) for c in mboss_cells + gboss_cells]
    pools += [list(t.get_flattened_data()) for t in tiles]
    pal = build_palette(pools, n=15)
    print("  palette (RGB333):", " ".join(f"{r}{g}{b}" for r, g, b in pal))

    # ---- sprites -------------------------------------------------------
    patterns, colours, names = [], [], []

    def add_sprite(cell, bg, label, two_layer=True, drop=()):
        (mA, cA), (mB, cB) = sprite_layers(cell, bg, pal, drop)
        patterns.append(pattern_bytes(mA))
        colours.append(cA)
        names.append(label + "_A")
        if two_layer:
            patterns.append(pattern_bytes(mB))
            # IC=1 (bit 5): this plane is only decoration, keep it out of the
            # hardware collision flag. Collisions are done in software.
            colours.append([(c | 0x20) if c else 0 for c in cB])
            names.append(label + "_B")

    for i, c in enumerate(player_cells):
        add_sprite(c, MSX_BG, f"PLAYER{i}", two_layer=True)
    for i, c in enumerate(enemy_cells):
        add_sprite(c, NES_BG, f"ENEMY{i}", two_layer=False)
    # Bullets are single-plane to keep the sprite budget for enemies. Their
    # black outline is dropped: on a one-colour-per-line plane the outline is
    # the most common colour on most lines, so it would win the line and leave
    # the bullet invisible against the black background.
    add_sprite(pbullet_cell, MSX_BG, "PBULLET", two_layer=False, drop=((0, 0, 0),))
    add_sprite(ebullet_cell, MSX_BG, "EBULLET", two_layer=False, drop=((0, 0, 0),))

    # Boss cells are single-plane: twelve cells x two planes would not fit in
    # the 32 hardware sprites, let alone the 8-per-line budget.
    for i, c in enumerate(mboss_cells):
        add_sprite(c, NES_BG, f"MBOSS{i}", two_layer=False)
    for i, c in enumerate(gboss_cells):
        add_sprite(c, NES_BG, f"GBOSS{i}", two_layer=False)

    # HUD glyphs are generated rather than lifted from the sheets. Their colour
    # comes from the sprite colour table, which the game writes, so the masks
    # carry a placeholder index here.
    white = nearest(pal, (255, 255, 255))
    for d in range(10):
        patterns.append(pattern_bytes(digit_mask(d)))
        colours.append([white] * 16)
        names.append(f"DIGIT{d}")
    for i, rows in enumerate(LABEL_FONT):
        patterns.append(pattern_bytes(glyph_mask(rows, DIGIT_W)))
        colours.append([white] * 16)
        names.append(f"LABEL{i}")            # 0 = F, 1 = C
    green = nearest(pal, (0, 255, 0))
    for k in range(17):
        patterns.append(pattern_bytes(energy_mask(k)))
        colours.append([green] * 16)
        names.append(f"ENERGY{k}")
    for i, rows in enumerate(LETTER_FONT):
        patterns.append(pattern_bytes(glyph_mask(rows, LETTER_W)))
        colours.append([white] * 16)
        names.append(f"LET{i}")

    # ---- tiles ---------------------------------------------------------
    tile_data = []
    for t in tiles:
        p = t.load()
        for y in range(16):
            for x in range(0, 16, 2):
                hi = nearest_dithered(pal, p[x, y], x, y)
                lo = nearest_dithered(pal, p[x + 1, y], x + 1, y)
                tile_data.append((hi << 4) | lo)

    # ---- palette bytes for the VDP ------------------------------------
    # V9938 palette format is two bytes per colour: (R<<4)|B then G.
    pal_bytes = []
    for r, g, b in pal:
        pal_bytes += [(r << 4) | b, g]

    # ---- write the asm include ----------------------------------------
    os.makedirs(SRCOUT, exist_ok=True)

    # Equates go in their own file so main.asm can include them before the
    # code that uses them, and the bulk data after it.
    consts = [
        "; gfx/convert.py 가 생성한 파일입니다. 직접 고치지 마세요.",
        "",
        f"TILE_COUNT    equ {len(tiles)}",
        f"MAP_ROWS      equ {len(tilemap)}",
        f"MAP_COLS      equ {len(tilemap[0])}",
        f"SPR_PAT_COUNT equ {len(patterns)}",
        "",
        "; 보스 격자 크기는 main.asm이 아니라 여기에 있어야 합니다. 게임은 첫 보스",
        "; 패턴부터 격자 한 칸에 셀 하나씩 그리므로, 이 값이 실제로 자른 모양과",
        "; 어긋나면 보스 패턴 끝을 넘어가고 스프라이트 슬롯 범위도 벗어납니다.",
        f"MBOSS_COLS   equ {mboss_grid[0]}",
        f"MBOSS_ROWS   equ {mboss_grid[1]}",
        f"GBOSS_COLS   equ {gboss_grid[0]}",
        f"GBOSS_ROWS   equ {gboss_grid[1]}",
        "",
    ]
    for i, n in enumerate(names):
        consts.append(f"PAT_{n} equ {i}")
    # encoding must be explicit: the comments are Korean, and Python would
    # otherwise use the console codepage, which cannot encode Hangul.
    with open(os.path.join(SRCOUT, "gfxconst.asm"), "w", encoding="utf-8") as f:
        f.write("\n".join(consts) + "\n")

    parts = [
        "; gfx/convert.py 가 생성한 파일입니다. 직접 고치지 마세요.",
        "",
        db("PaletteData", pal_bytes),
        "",
        db("SpritePatterns", [b for p in patterns for b in p]),
        "",
        db("SpriteColours", [b for c in colours for b in c]),
        "",
        # 256-byte aligned so the renderer can find a tile's pixel row with
        # 8-bit arithmetic: high byte = base + tile/2, low byte = the rest.
        "; 256바이트 정렬. 렌더러가 타일의 픽셀 행 주소를 8비트 연산만으로 구합니다",
        "; (상위 바이트 = 시작 + 타일/2, 하위 바이트 = 나머지).",
        "    ALIGN 256",
        db("TileData", tile_data),
        "",
        db("TileMap", [v for row in tilemap for v in row], per_line=len(tilemap[0])),
        "",
    ]
    with open(os.path.join(SRCOUT, "gfxdata.asm"), "w", encoding="utf-8") as f:
        f.write("\n".join(parts) + "\n")

    # 16x16 sprites consume four pattern numbers each, and pattern numbers are
    # a byte, so 64 is the hard ceiling.
    if len(patterns) > 64:
        raise SystemExit(f"{len(patterns)} sprite patterns - the VDP allows 64 "
                         f"at 16x16 (pattern number is 8 bits, 4 per sprite)")
    print(f"  wrote src/gfxdata.asm: {len(patterns)}/64 sprite planes "
          f"({len(patterns) * 32} bytes), {len(tiles)} tiles "
          f"({len(tile_data)} bytes), map {len(tilemap)}x{len(tilemap[0])}")

    # ---- converted preview PNGs ---------------------------------------
    write_previews()


def write_previews():
    """Write each whole source sheet converted to an MSX2 palette.

    Each image gets its OWN 16-colour palette, derived from that image. The
    game's palette is deliberately different: it is built only from the assets
    the game actually uses, so its 15 slots are spent where they matter.

    Using the game's palette here would be wrong - it contains no green, and
    three of the four fortress screenshots are largely green, so they would all
    collapse to the same olive. Per-image palettes are also what makes the
    dithering do real work: the fortress sheet has more distinct colours than
    slots, so colours genuinely have to be merged and dithered back.
    """
    def convert(path, out, bg, dither, label):
        im = Image.open(path).convert("RGB")
        pool = [c for c in im.get_flattened_data() if bg is None or c != bg]
        pal = build_palette([pool], n=15, label=label)
        p = im.load()
        res = Image.new("RGB", im.size)
        rp = res.load()
        for y in range(im.height):
            for x in range(im.width):
                c = p[x, y]
                if bg is not None and c == bg:
                    rp[x, y] = bg
                    continue
                i = nearest_dithered(pal, c, x, y) if dither else nearest(pal, c)
                rp[x, y] = rgb333_to_rgb888(pal[i])
        res.save(out)
        print(f"    -> {os.path.basename(out)} "
              f"({'ordered dither' if dither else 'nearest-colour, no dither'})")

    # Sprite sheets are pixel art: nearest-colour keeps the silhouettes crisp.
    convert(MSX_SHEET, os.path.join(IMAGES, "msx_zanac_dither.png"),
            MSX_BG, dither=False, label="msx_zanac")
    convert(NES_SHEET, os.path.join(IMAGES, "nes_zanac_dither.png"),
            NES_BG, dither=False, label="nes_zanac")
    # Photographic-ish screenshot with more colours than slots: dither.
    convert(FORTRESS, os.path.join(IMAGES, "zanac-fortresses_dither.png"),
            None, dither=True, label="fortresses")


if __name__ == "__main__":
    print("converting Zanac reference art to MSX2 SCREEN 5 data")
    main()
