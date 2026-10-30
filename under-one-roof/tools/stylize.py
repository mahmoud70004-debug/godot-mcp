"""Converts generated sprites to the painted look of the art-direction reference.

All game textures are stored at RES x world resolution (sprites are drawn at 1/RES scale),
so painted detail stays sharp on phone screens.

  painted(img)     procedural sprite -> soft painted sprite (smooth edges, muted earthy
                   palette, soft top-left light), RES x larger
  upscale_ref(img) cut-out from the reference -> RES x larger, sharpened
"""
import numpy as np
import cv2
from PIL import Image
from smooth import painterize

RES = 2


def grade(rgb):
    """Pull colours towards the reference: less saturation, warmer olive midtones."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    hsv[..., 1] *= 0.78
    hsv[..., 2] = np.clip(hsv[..., 2] * 0.94 + 4, 0, 255)
    out = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB).astype(np.float32)
    out = out * np.array([1.03, 1.0, 0.9]) + np.array([4, 3, -2])
    return np.clip(out, 0, 255).astype(np.uint8)


def painted(img, seed=0):
    """Procedural RGBA sprite -> painted RGBA at RES x size."""
    img = img.convert("RGBA")
    w, h = img.size
    big = painterize(img, seed=seed, texture=0.03)           # 4x
    a = np.array(big)
    rgb = grade(a[..., :3])
    # soft light from the top-left across the whole silhouette
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]].astype(np.float32)
    light = 1.06 - 0.12 * (yy / a.shape[0]) - 0.05 * (xx / a.shape[1])
    rgb = np.clip(rgb * light[..., None], 0, 255).astype(np.uint8)
    out = Image.fromarray(np.dstack([rgb, a[..., 3]]))
    return out.resize((w * RES, h * RES), Image.LANCZOS)


def painted_frames(img, fw, fh, seed=0):
    """Paint every frame of a sheet separately (no bleeding between frames)."""
    img = img.convert("RGBA")
    cols, rows = img.width // fw, img.height // fh
    out = Image.new("RGBA", (img.width * RES, img.height * RES))
    for r in range(rows):
        for c in range(cols):
            f = img.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
            if f.getbbox() is None:
                continue
            out.alpha_composite(painted(f, seed + r * cols + c), (c * fw * RES, r * fh * RES))
    return out


def upscale_ref(img):
    a = np.array(img.convert("RGBA"))
    w, h = img.size
    rgb = cv2.resize(a[..., :3], (w * RES, h * RES), interpolation=cv2.INTER_CUBIC)
    blur = cv2.GaussianBlur(rgb.astype(np.float32), (0, 0), 1.0)
    rgb = np.clip(rgb * 1.5 - blur * 0.5, 0, 255).astype(np.uint8)
    al = cv2.resize(a[..., 3], (w * RES, h * RES), interpolation=cv2.INTER_LINEAR)
    return Image.fromarray(np.dstack([rgb, al]))
