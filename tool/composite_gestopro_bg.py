"""Piazza il marchio GESTOPRO360 a sinistra sugli sfondi treno."""
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets"
MARK = ROOT / "gestopro360_watermark.png"
GEN = Path(
    r"C:\Users\alexandru.cibuc\.cursor\projects"
    r"\c-flutter-projects-organizzazione-personale-cronos-mod\assets"
)


def knock_out_background(im: Image.Image, tol: float = 38.0) -> Image.Image:
    im = im.convert("RGBA")
    pix = im.load()
    w, h = im.size
    sr, sg, sb, _ = pix[0, 0]
    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque([(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    while q:
        x, y = q.popleft()
        i = y * w + x
        if visited[i]:
            continue
        visited[i] = 1
        r, g, b, a = pix[x, y]
        if abs(r - sr) + abs(g - sg) + abs(b - sb) > tol * 3:
            continue
        pix[x, y] = (r, g, b, 0)
        if x > 0:
            q.append((x - 1, y))
        if x + 1 < w:
            q.append((x + 1, y))
        if y > 0:
            q.append((x, y - 1))
        if y + 1 < h:
            q.append((x, y + 1))
    return im


def crop_alpha(im: Image.Image) -> Image.Image:
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def paste_logo(
    bg: Image.Image,
    logo: Image.Image,
    *,
    width_frac: float,
    cx_frac: float,
    cy_frac: float,
) -> Image.Image:
    bg = bg.convert("RGBA")
    tw = max(1, int(bg.width * width_frac))
    ratio = logo.height / logo.width
    th = max(1, int(tw * ratio))
    mark = logo.resize((tw, th), Image.Resampling.LANCZOS)
    x = int(bg.width * cx_frac - tw / 2)
    y = int(bg.height * cy_frac - th / 2)
    bg.alpha_composite(mark, (x, y))
    return bg.convert("RGB")


def main() -> None:
    logo = crop_alpha(knock_out_background(Image.open(MARK)))
    land_src = GEN / "bg_train_landscape.png"
    port_src = GEN / "bg_train_portrait.png"
    land = paste_logo(
        Image.open(land_src),
        logo,
        width_frac=0.22,
        cx_frac=0.18,
        cy_frac=0.50,
    )
    port = paste_logo(
        Image.open(port_src),
        logo,
        width_frac=0.42,
        cx_frac=0.50,
        cy_frac=0.22,
    )
    land.save(ROOT / "bg_train_landscape.png", "PNG", optimize=True)
    port.save(ROOT / "bg_train_portrait.png", "PNG", optimize=True)
    print("wrote", land.size, port.size)


if __name__ == "__main__":
    main()
