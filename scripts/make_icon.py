"""Genera Resources/AppIcon.png (1024 px) a partir de una imagen con la cara naranja sobre fondo claro.

Uso:
    python3 scripts/make_icon.py original.png Resources/AppIcon.png

Después, para el .icns:
    mkdir AppIcon.iconset
    for s in 16 32 128 256 512; do
      sips -z $s $s Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}.png
      sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
    done
    iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns && rm -r AppIcon.iconset

Necesita Pillow (pip install pillow).
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
r, g, b = im.split()
# Cobertura de la cara: el azul cae de 255 (blanco) a ~0 (naranja).
# Cobertura de la cara: diferencia rojo-azul (blanco ≈ 0, naranja ≈ 255).
diff = ImageChops.subtract(r, b)
alpha = diff.point(lambda v: max(0, min(255, int((v - 25) * 255 / 200))))
# Quita motas sueltas: erosiona, vuelve a dilatar y usa eso como máscara.
core = alpha.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MinFilter(7))
region = core.filter(ImageFilter.MaxFilter(31))
alpha = ImageChops.multiply(alpha, region)
bbox = core.getbbox()
bbox = (bbox[0] - 4, bbox[1] - 4, bbox[2] + 4, bbox[3] + 4)
face_a = alpha.crop(bbox)
W = 1024; S4 = 4 * W
canvas = Image.new('RGBA', (S4, S4), (0, 0, 0, 0))
# Superelipse (n=5), cuerpo de 824 px como en la plantilla de iconos de macOS.
body = 824 * 4; off = (S4 - body) // 2
import math
pts = []
for i in range(720):
    t = 2 * math.pi * i / 720
    c, s = math.cos(t), math.sin(t)
    x = math.copysign(abs(c) ** (2 / 5), c); y = math.copysign(abs(s) ** (2 / 5), s)
    pts.append((off + body / 2 * (1 + x), off + body / 2 * (1 + y)))
mask = Image.new('L', (S4, S4), 0); ImageDraw.Draw(mask).polygon(pts, fill=255)
shadow = Image.new('RGBA', (S4, S4), (0, 0, 0, 0))
shadow.putalpha(ImageChops.offset(mask, 0, 32).filter(ImageFilter.GaussianBlur(48)).point(lambda v: v * 60 // 255))
canvas = Image.alpha_composite(canvas, shadow)
white = Image.new('RGBA', (S4, S4), (255, 255, 255, 255)); white.putalpha(mask)
canvas = Image.alpha_composite(canvas, white)
# Cara: 80 % del ancho del cuerpo, centrada (un pelín por debajo, como el original).
fw = int(body * 0.80); fh = int(face_a.height * fw / face_a.width)
face_a = face_a.resize((fw, fh), Image.LANCZOS)
face = Image.new('RGBA', (fw, fh), (255, 106, 0, 255)); face.putalpha(face_a)
layer = Image.new('RGBA', (S4, S4), (0, 0, 0, 0))
layer.paste(face, ((S4 - fw) // 2, (S4 - fh) // 2 + int(body * 0.01)), face)
canvas = Image.alpha_composite(canvas, layer)
canvas.resize((W, W), Image.LANCZOS).save(out)
print('cara', bbox, '->', fw // 4, 'x', fh // 4)
