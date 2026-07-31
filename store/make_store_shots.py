#!/usr/bin/env python3
"""Habille les captures brutes de TiConnect pour la fiche Play Store.

Usage :
    python3 make_store_shots.py                 # rendus avec placeholders
    python3 make_store_shots.py --src raw       # composite les vraies captures

Attend dans --src des fichiers nommes tel-01.png ... tel-08.png (l'ordre suit
la liste CAPTIONS ci-dessous). Toute capture manquante est remplacee par un
placeholder, ce qui permet de valider la maquette avant d'avoir l'app sous la
main.

Sortie : 1080x1920, PNG 24 bits sans canal alpha, conforme Play Console.
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1920

PRIMARY = (27, 94, 63)        # #1B5E3F
PRIMARY_DARK = (14, 61, 40)   # #0E3D28
ACCENT = (242, 160, 61)       # #F2A03D
WHITE = (255, 255, 255)

# (fichier source, titre, sous-titre)
CAPTIONS = [
    ("tel-01.png", "Trouvez l'ouvrier qu'il vous faut",
     "Des artisans qualifiés près de chez vous"),
    ("tel-02.png", "Le numéro se débloque gratuitement",
     "Avis, tarifs et coordonnées sur chaque profil"),
    ("tel-03.png", "Publiez votre besoin en deux minutes",
     "Décrivez le chantier, recevez des propositions"),
    ("tel-04.png", "Comparez, puis choisissez",
     "Les candidatures réunies au même endroit"),
    ("tel-05.png", "Échangez sans intermédiaire",
     "Une messagerie directe avec chaque artisan"),
    ("tel-06.png", "Ouvriers : les missions près de vous",
     "Un fil mis à jour en temps réel"),
    ("tel-07.png", "Des crédits, pas d'abonnement",
     "Vidéo récompensée ou recharge Mobile Money"),
    ("tel-08.png", "Un profil vérifié inspire confiance",
     "Badge de validation et note moyenne"),
]

FONT_CANDIDATES = {
    "bold": [
        "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
        "/System/Library/Fonts/Supplemental/Futura.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ],
    "regular": [
        "/usr/share/fonts/truetype/google-fonts/Poppins-Regular.ttf",
        "/System/Library/Fonts/Supplemental/Avenir.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ],
}


def load_font(kind, size):
    for path in FONT_CANDIDATES[kind]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def wrap(draw, text, font, max_width):
    words, lines, current = text.split(), [], ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def background():
    """Degrade vertical vert fonce -> vert primaire."""
    img = Image.new("RGB", (W, H), PRIMARY)
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        draw.line(
            [(0, y), (W, y)],
            fill=tuple(
                int(PRIMARY_DARK[i] + (PRIMARY[i] - PRIMARY_DARK[i]) * t)
                for i in range(3)
            ),
        )
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0], size[1]], radius, fill=255)
    return mask


def fit_cover(src, size):
    """Redimensionne en couvrant la zone, puis recadre au centre."""
    tw, th = size
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    resized = src.resize((max(1, round(sw * scale)), max(1, round(sh * scale))),
                         Image.LANCZOS)
    left = (resized.width - tw) // 2
    top = (resized.height - th) // 2
    return resized.crop((left, top, left + tw, top + th))


def placeholder(size, label):
    img = Image.new("RGB", size, (247, 248, 247))
    draw = ImageDraw.Draw(img)
    font = load_font("regular", 34)
    small = load_font("regular", 26)
    draw.rectangle([0, 0, size[0], 130], fill=PRIMARY)
    draw.text((40, 55), "TiConnect", font=load_font("bold", 38), fill=WHITE)
    for y in range(190, size[1] - 60, 150):
        draw.rounded_rectangle([40, y, size[0] - 40, y + 110], 18,
                               outline=(224, 229, 225), width=3)
    # Etiquette par-dessus le squelette, sur un fond plein pour rester lisible
    cx, cy = size[0] // 2, size[1] // 2
    draw.rounded_rectangle([cx - 260, cy - 70, cx + 260, cy + 70], 20,
                           fill=(255, 255, 255), outline=(224, 229, 225), width=3)
    draw.text((cx, cy - 22), label, font=font, fill=(120, 130, 122), anchor="mm")
    draw.text((cx, cy + 28), "capture à insérer", font=small,
              fill=(160, 168, 162), anchor="mm")
    return img


def build(index, src_dir, out_dir):
    filename, title, subtitle = CAPTIONS[index]
    img = background()
    draw = ImageDraw.Draw(img)

    title_font = load_font("bold", 62)
    sub_font = load_font("regular", 38)

    margin = 80
    y = 130

    for line in wrap(draw, title, title_font, W - 2 * margin):
        draw.text((W // 2, y), line, font=title_font, fill=WHITE, anchor="ma")
        y += 78

    y += 14
    draw.rounded_rectangle([W // 2 - 60, y, W // 2 + 60, y + 8], 4, fill=ACCENT)
    y += 46

    for line in wrap(draw, subtitle, sub_font, W - 2 * margin):
        draw.text((W // 2, y), line, font=sub_font, fill=(214, 226, 218),
                  anchor="ma")
        y += 52

    # Zone appareil : 9:16 exact, pour que la capture entre sans recadrage
    dev_w = 780
    dev_h = round(dev_w * 16 / 9)
    dev_x = (W - dev_w) // 2
    dev_y = H - dev_h - 64
    radius = 46

    source_path = os.path.join(src_dir, filename)
    if os.path.exists(source_path):
        shot = fit_cover(Image.open(source_path).convert("RGB"), (dev_w, dev_h))
    else:
        shot = placeholder((dev_w, dev_h), filename)

    shot.putalpha(rounded_mask((dev_w, dev_h), radius))

    # Contour blanc
    frame = Image.new("RGBA", (dev_w + 16, dev_h + 16), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, dev_w + 16, dev_h + 16], radius + 8, fill=WHITE + (235,)
    )
    img.paste(frame, (dev_x - 8, dev_y - 8), frame)
    img.paste(shot, (dev_x, dev_y), shot)

    out_path = os.path.join(out_dir, f"play-tel-{index + 1:02d}.png")
    img.convert("RGB").save(out_path, "PNG")  # RGB => aucun canal alpha
    return out_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default="raw", help="dossier des captures brutes")
    parser.add_argument("--out", default="out", help="dossier de sortie")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    missing = []
    for i in range(len(CAPTIONS)):
        path = build(i, args.src, args.out)
        if not os.path.exists(os.path.join(args.src, CAPTIONS[i][0])):
            missing.append(CAPTIONS[i][0])
        print("ecrit :", path)

    if missing:
        print("\nPlaceholders utilises (captures absentes de "
              f"{args.src}/) : {', '.join(missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()
