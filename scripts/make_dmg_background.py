"""Genera el fondo de la ventana del DMG (Resources/dmg-background.png y @2x).

Uso:
    python3 scripts/make_dmg_background.py

La app va a la izquierda y la carpeta Aplicaciones a la derecha; las posiciones tienen
que coincidir con `icon_locations` de scripts/dmg-settings.py. Necesita Pillow.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
W, H = 660, 400                     # tamaño de la ventana en puntos
APP_X, APPS_X, ICON_Y = 180, 480, 190
ORANGE = (255, 106, 0)
INK = (60, 60, 67)
FONT = "/System/Library/Fonts/SFNSRounded.ttf"


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def render(scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h), (250, 249, 247))
    d = ImageDraw.Draw(img)

    # Degradado muy suave hacia abajo.
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(250 - 6 * t), int(249 - 8 * t), int(247 - 10 * t)))

    # Icono y nombre arriba.
    icon = Image.open(ROOT / "Resources/AppIcon.png").convert("RGBA").resize((64 * scale, 64 * scale), Image.LANCZOS)
    img.paste(icon, (int(w / 2 - 32 * scale), 14 * scale), icon)
    d.text((w / 2, 90 * scale), "Claudio", font=font(17 * scale, "Semibold"), fill=INK, anchor="mm")

    # Flecha entre la app y Aplicaciones, con sombra suave.
    x0, x1, y = (APP_X + 82) * scale, (APPS_X - 82) * scale, ICON_Y * scale
    stroke, head = 7 * scale, 20 * scale
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.line([(x0, y), (x1 - head, y)], fill=ORANGE + (255,), width=stroke)
    ld.ellipse([x0 - stroke / 2, y - stroke / 2, x0 + stroke / 2, y + stroke / 2], fill=ORANGE + (255,))
    ld.polygon([(x1, y), (x1 - head * 1.3, y - head), (x1 - head * 1.3, y + head)], fill=ORANGE + (255,))
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(4 * scale)).point(lambda v: v * 50 // 255)
    img.paste((0, 0, 0), (0, 2 * scale), shadow)
    img.paste(layer, (0, 0), layer)

    # Instrucción abajo (los nombres de los iconos los pinta el Finder debajo de cada uno).
    d.text((w / 2, 338 * scale), "Drag Claudio to Applications", font=font(15 * scale, "Medium"),
           fill=INK, anchor="mm")
    d.text((w / 2, 362 * scale), "Arrastra Claudio a Aplicaciones", font=font(12 * scale, "Regular"),
           fill=(120, 120, 128), anchor="mm")
    return img


if __name__ == "__main__":
    render(1).save(ROOT / "Resources/dmg-background.png")
    render(2).save(ROOT / "Resources/dmg-background@2x.png")
    print("Resources/dmg-background.png y @2x listos")
