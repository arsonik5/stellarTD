"""Grid of every building's review render -> art_src/contact_sheet.png.
python art_src/contact_sheet.py   (needs Pillow)"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
# (folder, label, view) - pipes and turrets read best from the side their front faces
ITEMS = [
    ("smelter", "Smelter", "renders/smelter_hero.png"),
    ("crafter", "Crafter", "renders/crafter_hero.png"),
    ("constructor", "Constructor", "renders/constructor_hero.png"),
    ("chest", "Chest", "renders/chest_hero.png"),
    ("pipe", "Vacuum Pipe", "renders/pipe_hero.png"),
    ("merger", "Merger", "renders/merger_back.png"),
    ("splitter", "Splitter", "renders/splitter_back.png"),
    ("foundation", "Foundation", "renders/foundation_high.png"),
    ("turret_gun", "Gun Turret", "renders/turret_gun_back.png"),
    ("turret_cannon", "Cannon", "renders/turret_cannon_back.png"),
    ("ship_core", "Ship Core", "renders/ship_core_hero.png"),
    ("ship_cockpit", "Cockpit", "renders/ship_cockpit_back.png"),
    ("ship_hull", "Ship Hull", "renders/ship_hull_hero.png"),
    ("ship_gyroscope", "Gyroscope", "renders/ship_gyroscope_hero.png"),
    ("ship_thruster", "Thruster", "renders/ship_thruster_hero.png"),
    ("ship_garage", "Ship Garage", "renders/ship_garage_hero.png"),
]
TW, TH, COLS = 480, 360, 4
rows = (len(ITEMS) + COLS - 1) // COLS
sheet = Image.new("RGB", (TW * COLS, TH * rows), (12, 12, 16))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("arial.ttf", 22)
except OSError:
    font = ImageFont.load_default()
for i, (folder, label, rel) in enumerate(ITEMS):
    p = os.path.join(ROOT, folder, rel)
    x, y = (i % COLS) * TW, (i // COLS) * TH
    if os.path.exists(p):
        im = Image.open(p).convert("RGB")
        im.thumbnail((TW, TH))
        sheet.paste(im, (x + (TW - im.width) // 2, y + (TH - im.height) // 2))
    d.rectangle((x, y + TH - 34, x + TW, y + TH), fill=(0, 0, 0))
    d.text((x + 12, y + TH - 30), label, fill=(235, 235, 235), font=font)
out = os.path.join(ROOT, "contact_sheet.png")
sheet.save(out)
print(out)
