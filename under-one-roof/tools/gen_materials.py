"""Ground materials synthesised from samples of the art-direction reference image.

Each material is quilted from one or more clean sample rectangles of
assets/reference/world_reference.jpg and saved as a 512x512 tileable texture in
tools/materials/ (input for paint_ground.py; not shipped with the game).
"""
import os
import numpy as np
from PIL import Image
from texsynth import quilt, make_tileable

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "assets", "reference", "world_reference.jpg")
OUT = os.path.join(ROOT, "tools", "materials")

# material -> list of sample boxes (x0, y0, x1, y1) in reference pixels
QUILTED = {
    "cobble": [(1022, 125, 1082, 250), (1022, 275, 1082, 330)],
    "sea": [(1000, 640, 1100, 760)],
    "sea_deep": [(1150, 700, 1370, 768)],
    "river": [(15, 578, 265, 612), (745, 576, 995, 610)],
    "pond": [(85, 262, 135, 330)],
}
# painted materials: palette sampled from the reference, strokes generated
PAINTED = {
    "grass": [(455, 205, 530, 300)],
    "grass_dark": [(170, 440, 250, 500)],
    "dirt": [(312, 670, 326, 760)],
    "sand": [(1070, 503, 1270, 518)],
}


def sample_stack(im, boxes):
    """Concatenate samples side by side (padded to the same height)."""
    crops = [np.array(im.crop(b)) for b in boxes]
    h = min(c.shape[0] for c in crops)
    return np.concatenate([c[:h] for c in crops], axis=1)


def palette(pixels, k=6, seed=0):
    """k-means colours of a sample, sorted dark -> light."""
    rng = np.random.default_rng(seed)
    px = pixels.reshape(-1, 3).astype(np.float32)
    cent = px[rng.choice(len(px), k, replace=False)]
    for _ in range(20):
        d = ((px[:, None, :] - cent[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for j in range(k):
            if (lab == j).any():
                cent[j] = px[lab == j].mean(0)
    order = np.argsort(cent.sum(1))
    return cent[order]


def periodic_noise(size, cells, rng):
    """Smooth value noise that wraps around (tileable)."""
    g = rng.random((cells, cells))
    t = np.arange(size) * cells / size
    i0 = t.astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - t.astype(int)
    f = f * f * (3 - 2 * f)
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def paint_material(pal, size, seed, strokes=9000, stroke_len=(2, 5)):
    """Mottled base from the palette + thousands of short soft brush strokes (wrapping)."""
    from PIL import ImageDraw, ImageFilter
    rng = np.random.default_rng(seed)
    n = periodic_noise(size, 6, rng) * 0.6 + periodic_noise(size, 16, rng) * 0.3 + periodic_noise(size, 40, rng) * 0.1
    n = (n - n.min()) / (n.max() - n.min())
    idx = n * (len(pal) - 1.001)
    lo = idx.astype(int)
    fr = (idx - lo)[..., None]
    base = pal[lo] * (1 - fr) + pal[np.minimum(lo + 1, len(pal) - 1)] * fr
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")
    big = Image.new("RGBA", (size * 3, size * 3))
    for ox in range(3):
        for oy in range(3):
            big.paste(img, (ox * size, oy * size))
    d = ImageDraw.Draw(big, "RGBA")
    for _ in range(strokes):
        x, y = rng.integers(size, size * 2), rng.integers(size, size * 2)
        local = n[y % size, x % size]
        j = int(np.clip(local * (len(pal) - 1) + rng.normal(0, 1.1), 0, len(pal) - 1))
        col = tuple(int(c) for c in pal[j]) + (int(rng.integers(90, 200)),)
        ang = rng.normal(-1.3, 0.5)
        L = rng.uniform(*stroke_len)
        for wx in (-size, 0, size):
            for wy in (-size, 0, size):
                d.line([(x + wx, y + wy), (x + wx + np.cos(ang) * L, y + wy + np.sin(ang) * L)], fill=col, width=int(rng.integers(1, 3)))
    out = big.crop((size, size, size * 2, size * 2)).filter(ImageFilter.SMOOTH)
    return np.array(out.convert("RGB"))


def build(size=512):
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(REF).convert("RGB")
    for i, (name, boxes) in enumerate(PAINTED.items()):
        pal = palette(sample_stack(im, boxes), k=6, seed=i)
        tex = paint_material(pal, size, seed=100 + i, strokes=18000 if "grass" in name else 5000,
                             stroke_len=(2, 6) if "grass" in name else (1, 3))
        Image.fromarray(tex).save(os.path.join(OUT, f"{name}.png"))
        print("painted", name)
    for i, (name, boxes) in enumerate(QUILTED.items()):
        s = sample_stack(im, boxes)
        patch = max(12, min(40, s.shape[0] - 2, s.shape[1] - 2))
        tex = quilt(s, size, patch=patch, overlap=max(4, patch // 4), seed=i)
        tex = make_tileable(tex, band=40)
        Image.fromarray(tex).save(os.path.join(OUT, f"{name}.png"))
        print("material", name, s.shape)


if __name__ == "__main__":
    build()
