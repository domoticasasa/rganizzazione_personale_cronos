"""
Genera assets/icon_tray.ico e assets/icon_tray_notify.ico:
stesso layout e stesse dimensioni del testo; solo il colore cambia
(nero = nessuna notifica non letta, rosso = notifica da leggere).

Esegue: python tools/generate_tray_icons.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZES = (16, 24, 32, 48, 64)
TEXT = "Cronos"
COLOR_IDLE = (20, 20, 20)  # nero quasi pieno su bianco
COLOR_NOTIFY = (200, 30, 30)  # rosso ben visibile
BG = (255, 255, 255)


def _windows_font() -> str | None:
    windir = os.environ.get("WINDIR", r"C:\Windows")
    for name in ("arialbd.ttf", "arial.ttf", "segoeuib.ttf", "segoeui.ttf"):
        p = Path(windir) / "Fonts" / name
        if p.is_file():
            return str(p)
    return None


def _fit_font(
    size: int,
    text: str,
    font_path: str | None,
) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Stessa logica per idle e notify: proporzione fissa alla tile."""
    margin = max(1, size // 16)
    max_w = size - 2 * margin
    max_h = size - 2 * margin
    # Per tile molto piccole usa una sola lettera, stesso ingombro relativo.
    label = text if size >= 28 else "C"
    for fs in range(size, 5, -1):
        try:
            if font_path:
                font = ImageFont.truetype(font_path, fs)
            else:
                font = ImageFont.load_default()
        except OSError:
            font = ImageFont.load_default()
        bbox = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), label, font=font)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        if w <= max_w and h <= max_h:
            return font
    return ImageFont.load_default()


def _render_tile(px: int, text_color: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (px, px), BG)
    draw = ImageDraw.Draw(img)
    font_path = _windows_font()
    font = _fit_font(px, TEXT, font_path)
    label = TEXT if px >= 28 else "C"
    bbox = draw.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (px - tw) // 2 - bbox[0]
    y = (px - th) // 2 - bbox[1]
    draw.text((x, y), label, fill=text_color, font=font)
    return img


def _write_ico(path: Path, text_color: tuple[int, int, int]) -> None:
    tiles = [_render_tile(s, text_color) for s in SIZES]
    first = tiles[0]
    first.save(
        path,
        format="ICO",
        sizes=[(t.width, t.height) for t in tiles],
        append_images=tiles[1:],
        bitmap_format="bmp",
    )


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    assets = root / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    _write_ico(assets / "icon_tray.ico", COLOR_IDLE)
    _write_ico(assets / "icon_tray_notify.ico", COLOR_NOTIFY)
    print(f"OK: wrote {assets / 'icon_tray.ico'} (testo nero)")
    print(f"OK: wrote {assets / 'icon_tray_notify.ico'} (testo rosso)")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(e, file=sys.stderr)
        sys.exit(1)
