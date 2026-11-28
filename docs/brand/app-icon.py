# The Nourlo app icon: the app's own mascot (MascotFigure, happy), peeking up from the bottom
# on the almond background, with no name. The owner chose this on 17 Nov 2026.
#
# docs/brand/mascot-happy.png comes from the app's drawing code: run the test
# MascotSnapshotTests/testRenderIconMascot, then copy /tmp/mealio-run/mascot/mascot-icon-happy.png.
# Run from the repo root: python3 -I docs/brand/app-icon.py   (needs Pillow)
from PIL import Image, ImageDraw, ImageFilter

MASCOT = Image.open("docs/brand/mascot-happy.png").convert("RGBA")
UNIT = 3.0       # pixels per design unit in that render
ORIGIN = 128     # the render's canvas starts 128 units before the design space


def icon(size=1024):
    im = Image.new("RGB", (1024, 1024), (244, 218, 212))  # almond, lighter towards the top
    ImageDraw.Draw(im).ellipse((112, -40, 912, 640), fill=(251, 237, 232))
    im = im.filter(ImageFilter.GaussianBlur(150)).convert("RGBA")
    # 2.5 px a design unit; the top of the fruit (design y 58) sits at y 230, so the whole smile shows.
    scale = 2.5 / UNIT
    m = MASCOT.resize((round(MASCOT.width * scale), round(MASCOT.height * scale)), Image.LANCZOS)
    x = round(512 - (ORIGIN + 256) * 2.5)
    y = round(230 - (ORIGIN + 58) * 2.5)
    layer = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    layer.paste(m, (x, y), m)
    im.alpha_composite(layer)
    out = im.convert("RGB")  # the App Store icon must have no transparency
    return out if size == 1024 else out.resize((size, size), Image.LANCZOS)


master = icon()
master.save("smartmarket/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
icon(288).save("smartmarket/Assets.xcassets/BrandLogo.imageset/brand-logo.png")
# The website's favicon follows the icon, with rounded corners.
fav = master.convert("RGBA")
mask = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 1023, 1023], radius=230, fill=255)
fav.putalpha(mask)
fav.save("web/app/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (256, 256)])
print("ok")
