#!/usr/bin/env python3
"""Maquettes des 8 écrans TiConnect, reconstruites d'après le code Dart.

Sortie : raw/tel-01.png … raw/tel-08.png en 1080×1920 (densité 3x, soit
360 dp de large — la mise en page suit les valeurs en dp du code source).

Les structures reprennent les widgets réels : WorkerCard et RatingStars de
lib/widgets/common.dart, les libellés des AppBar et des champs, les chips de
catégories issues de la table trade_categories, les formats de Fmt (prix,
distance, temps relatif).

Ce ne sont pas des captures : à remplacer par de vraies captures dès qu'un
émulateur est disponible.
"""

import os

from PIL import Image, ImageDraw, ImageFont

S = 3  # densité : 1 dp = 3 px
W, H = 360 * S, 640 * S

PRIMARY = (27, 94, 63)
PRIMARY_DK = (14, 61, 40)
ACCENT = (242, 160, 61)
SURFACE = (247, 248, 247)
BORDER = (221, 226, 222)
CARD_BORDER = (230, 234, 231)
INK = (17, 24, 20)
INK54 = (110, 118, 112)
INK45 = (132, 140, 134)
WHITE = (255, 255, 255)

FONTS = {
    "b": ["/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "m": ["/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf",
          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "r": ["/usr/share/fonts/truetype/google-fonts/Poppins-Regular.ttf",
          "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"],
}
_cache = {}


def F(kind, dp):
    key = (kind, dp)
    if key not in _cache:
        for p in FONTS[kind]:
            if os.path.exists(p):
                _cache[key] = ImageFont.truetype(p, int(dp * S))
                break
        else:
            _cache[key] = ImageFont.load_default()
    return _cache[key]


# ---------------------------------------------------------------- primitives

def new_screen():
    img = Image.new("RGB", (W, H), SURFACE)
    return img, ImageDraw.Draw(img)


def status_bar(d, color=WHITE):
    d.text((16 * S, 14 * S), "9:41", font=F("m", 11), fill=color)
    x = W - 52 * S
    for i, h in enumerate((4, 6, 8, 10)):          # signal
        d.rectangle([x + i * 5 * S, 22 * S - h * S, x + i * 5 * S + 3 * S, 22 * S],
                    fill=color)
    d.rounded_rectangle([W - 28 * S, 13 * S, W - 12 * S, 22 * S], 2 * S,
                        outline=color, width=S)
    d.rectangle([W - 26 * S, 15 * S, W - 17 * S, 20 * S], fill=color)


def app_bar(d, title, back=False):
    d.rectangle([0, 0, W, 84 * S], fill=PRIMARY)
    status_bar(d)
    tx = 16 * S
    if back:
        cx, cy = 22 * S, 58 * S
        d.line([cx + 5 * S, cy - 6 * S, cx - 2 * S, cy, cx + 5 * S, cy + 6 * S],
               fill=WHITE, width=2 * S, joint="curve")
        tx = 44 * S
    d.text((tx, 46 * S), title, font=F("b", 17), fill=WHITE)


def card(d, x, y, w, h, radius=14):
    d.rounded_rectangle([x, y, x + w, y + h], radius * S, fill=WHITE,
                        outline=CARD_BORDER, width=S)


def chip(d, x, y, label, selected=False, font=None, pad=12):
    font = font or F("m", 12)
    tw = d.textlength(label, font=font)
    w = tw + 2 * pad * S
    h = 32 * S
    if selected:
        d.rounded_rectangle([x, y, x + w, y + h], 8 * S, fill=PRIMARY)
        d.text((x + pad * S, y + 8 * S), label, font=font, fill=WHITE)
    else:
        d.rounded_rectangle([x, y, x + w, y + h], 8 * S, fill=WHITE,
                            outline=BORDER, width=S)
        d.text((x + pad * S, y + 8 * S), label, font=font, fill=INK)
    return w


def elide(d, text, font, maxw):
    """Equivalent de TextOverflow.ellipsis sur une ligne."""
    if d.textlength(text, font=font) <= maxw:
        return text
    while text and d.textlength(text + "…", font=font) > maxw:
        text = text[:-1]
    return text.rstrip() + "…"


def avatar(d, cx, cy, r, initial):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(226, 236, 230))
    f = F("b", 20)
    d.text((cx, cy), initial, font=f, fill=PRIMARY, anchor="mm")


def star(d, cx, cy, r, fill=ACCENT):
    import math
    pts = []
    for i in range(10):
        ang = math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rad * math.cos(ang), cy - rad * math.sin(ang)))
    d.polygon(pts, fill=fill)


def rating(d, x, y, value, count):
    """Reproduit RatingStars : étoile accent, note, (n)."""
    if count == 0:
        d.text((x, y), "Nouveau", font=F("r", 12), fill=INK54)
        return
    star(d, x + 7 * S, y + 8 * S, 8 * S)
    d.text((x + 18 * S, y), f"{value:.1f}", font=F("m", 12), fill=INK)
    w = d.textlength(f"{value:.1f}", font=F("m", 12))
    d.text((x + 22 * S + w, y + S), f"({count})", font=F("r", 11), fill=INK54)


def verified(d, cx, cy, r=8):
    r = r * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=PRIMARY)
    d.line([cx - 3.5 * S, cy, cx - S, cy + 3 * S, cx + 4 * S, cy - 3.5 * S],
           fill=WHITE, width=int(1.6 * S), joint="curve")


def button(d, x, y, w, label, filled=True, h=44):
    h = h * S
    if filled:
        d.rounded_rectangle([x, y, x + w, y + h], 10 * S, fill=PRIMARY)
        d.text((x + w / 2, y + h / 2), label, font=F("m", 14), fill=WHITE,
               anchor="mm")
    else:
        d.rounded_rectangle([x, y, x + w, y + h], 10 * S, fill=WHITE,
                            outline=PRIMARY, width=int(1.4 * S))
        d.text((x + w / 2, y + h / 2), label, font=F("m", 14), fill=PRIMARY,
               anchor="mm")


def bottom_nav(d, items, active):
    top = H - 68 * S
    d.rectangle([0, top, W, H], fill=WHITE)
    d.line([0, top, W, top], fill=BORDER, width=S)
    step = W / len(items)
    for i, label in enumerate(items):
        cx = step * (i + 0.5)
        col = PRIMARY if i == active else INK45
        if i == active:
            d.rounded_rectangle([cx - 26 * S, top + 8 * S, cx + 26 * S,
                                 top + 32 * S], 12 * S,
                                fill=(226, 236, 230))
        d.ellipse([cx - 7 * S, top + 13 * S, cx + 7 * S, top + 27 * S],
                  outline=col, width=int(1.6 * S))
        d.text((cx, top + 44 * S), label, font=F("m", 10), fill=col, anchor="mm")


def field(d, x, y, w, hint, value=None, h=52):
    h = h * S
    d.rounded_rectangle([x, y, x + w, y + h], 10 * S, fill=WHITE,
                        outline=BORDER, width=S)
    d.text((x + 14 * S, y + h / 2), value or hint, font=F("r", 13),
           fill=INK if value else INK45, anchor="lm")
    return y + h


def label(d, x, y, text):
    d.text((x, y), text, font=F("m", 12), fill=INK54)
    return y + 20 * S


# ------------------------------------------------------------------- données

WORKERS = [
    ("Ibrahim Traoré", "Maçon · 12 ans de chantier", 4.8, 23, 41,
     "15 000 – 25 000 XOF /jour", "2,3 km", True, True),
    ("Kouadio N'Guessan", "Électricien bâtiment · dépannage 24h", 4.6, 17, 28,
     "10 000 – 18 000 XOF /jour", "3,8 km", True, False),
    ("Mariam Bamba", "Ménage / Entretien · bureaux et maisons", 4.9, 31, 64,
     "2 500 – 4 000 XOF /heure", "1,2 km", True, False),
    ("Yao Kouassi", "Plombier · sanitaire et réseaux", 4.4, 9, 12,
     "12 000 – 20 000 XOF /jour", "5,1 km", False, False),
    ("Seydou Coulibaly", "Carreleur · faïence et grès", 0, 0, 0,
     "À négocier au forfait", "6,7 km", False, False),
]

CATEGORIES = ["Bâtiment & Construction", "Transport & Livraison",
              "Maison & Entretien", "Réparation & Technique"]

CLIENT_TABS = ["Chercher", "Demandes", "Messages", "Compte"]
WORKER_TABS = ["Missions", "Messages", "Compte"]


# -------------------------------------------------------------------- écrans

def screen_search():
    img, d = new_screen()
    app_bar(d, "Trouver un ouvrier")

    y = 96 * S
    d.rounded_rectangle([16 * S, y, W - 16 * S, y + 52 * S], 10 * S, fill=WHITE,
                        outline=BORDER, width=S)
    d.ellipse([28 * S, y + 18 * S, 42 * S, y + 32 * S], outline=INK45,
              width=int(1.6 * S))
    d.line([41 * S, y + 31 * S, 46 * S, y + 36 * S], fill=INK45, width=int(1.6 * S))
    d.text((56 * S, y + 26 * S), "Maçon, chauffeur, plombier…", font=F("r", 13),
           fill=INK45, anchor="lm")

    y += 64 * S
    x = 12 * S
    x += chip(d, x, y, "Disponibles", True) + 8 * S
    for c in CATEGORIES:
        x += chip(d, x, y, c) + 8 * S
        if x > W:
            break

    y += 46 * S
    for name, headline, rate, count, jobs, price, dist, verif, boost in WORKERS:
        h = 96 * S
        card(d, 12 * S, y, W - 24 * S, h)
        avatar(d, 12 * S + 42 * S, y + h / 2, 28 * S, name[0])
        tx = 12 * S + 84 * S + 14 * S
        d.text((tx, y + 16 * S), name, font=F("m", 15), fill=INK)
        nw = d.textlength(name, font=F("m", 15))
        cx = tx + nw + 10 * S
        if verif:
            verified(d, cx + 8 * S, y + 24 * S)
            cx += 24 * S
        if boost and cx + 56 * S < W - 76 * S:
            d.rounded_rectangle([cx, y + 17 * S, cx + 56 * S, y + 31 * S], 4 * S,
                                fill=(252, 234, 210))
            d.text((cx + 28 * S, y + 24 * S), "EN AVANT", font=F("b", 8),
                   fill=(150, 95, 20), anchor="mm")
        d.text((tx, y + 38 * S),
               elide(d, headline, F("r", 12), W - tx - 76 * S),
               font=F("r", 12), fill=INK54)
        rating(d, tx, y + 58 * S, rate, count)
        if jobs:
            d.text((tx + 92 * S, y + 59 * S), f"{jobs} missions", font=F("r", 11),
                   fill=INK54)
        d.text((tx, y + 76 * S), price, font=F("m", 12), fill=INK)
        # distance : dernier enfant de la Row, centré verticalement
        d.text((W - 20 * S, y + h / 2), dist, font=F("r", 11), fill=INK45,
               anchor="rm")
        y += h + 10 * S

    bottom_nav(d, CLIENT_TABS, 0)
    return img


def screen_worker_detail():
    img, d = new_screen()
    app_bar(d, "Ibrahim Traoré", back=True)

    d.rectangle([0, 84 * S, W, 300 * S], fill=WHITE)
    avatar(d, W / 2, 150 * S, 44 * S, "I")
    d.text((W / 2, 212 * S), "Ibrahim Traoré", font=F("b", 19), fill=INK,
           anchor="ma")
    verified(d, W / 2 + d.textlength("Ibrahim Traoré", font=F("b", 19)) / 2 + 14 * S,
             220 * S, 9)
    d.text((W / 2, 240 * S), "Maçon · 12 ans de chantier", font=F("r", 13),
           fill=INK54, anchor="ma")
    rating(d, W / 2 - 40 * S, 264 * S, 4.8, 23)
    d.text((W / 2 + 44 * S, 264 * S), "41 missions", font=F("r", 11), fill=INK54)

    y = 316 * S
    d.text((20 * S, y), "15 000 – 25 000 XOF /jour", font=F("b", 16), fill=PRIMARY)
    d.text((20 * S, y + 26 * S), "Abidjan · Cocody  ·  intervient sous 24 h",
           font=F("r", 12), fill=INK54)

    y += 62 * S
    bw = (W - 40 * S - 10 * S) / 2
    button(d, 20 * S, y, bw, "Appeler")
    button(d, 20 * S + bw + 10 * S, y, bw, "Message", filled=False)
    y += 56 * S
    button(d, 20 * S, y, W - 40 * S, "Voir le numéro (gratuit)", filled=False)

    y += 68 * S
    d.text((20 * S, y), "Avis", font=F("b", 15), fill=INK)
    y += 28 * S
    for who, note, txt in [
        ("Awa K.", 5.0, "Mur terminé en trois jours, chantier propre."),
        ("Bakary S.", 4.5, "Bon travail, ponctuel. Devis respecté."),
    ]:
        card(d, 12 * S, y, W - 24 * S, 74 * S)
        avatar(d, 12 * S + 32 * S, y + 37 * S, 20 * S, who[0])
        d.text((66 * S, y + 16 * S), who, font=F("m", 13), fill=INK)
        rating(d, 66 * S, y + 36 * S, note, 1)
        d.text((66 * S, y + 54 * S), txt, font=F("r", 11), fill=INK54)
        y += 84 * S

    return img


def screen_job_create():
    img, d = new_screen()
    app_bar(d, "Publier une demande", back=True)

    x, w = 20 * S, W - 40 * S
    y = 104 * S
    y = label(d, x, y, "Quel métier ?")
    y = field(d, x, y, w, "Choisir un métier", "Maçon") + 16 * S
    y = label(d, x, y, "Titre")
    y = field(d, x, y, w, "Construction mur de clôture",
              "Construction mur de clôture") + 16 * S
    y = label(d, x, y, "Description")
    d.rounded_rectangle([x, y, x + w, y + 96 * S], 10 * S, fill=WHITE,
                        outline=BORDER, width=S)
    for i, line in enumerate([
            "Mur de 18 m sur 2 m, parpaings fournis.",
            "Terrain plat, accès camion possible.",
            "Démarrage souhaité sous une semaine."]):
        d.text((x + 14 * S, y + 16 * S + i * 22 * S), line, font=F("r", 12),
               fill=INK)
    y += 112 * S

    hw = (w - 12 * S) / 2
    label(d, x, y, "Ville")
    label(d, x + hw + 12 * S, y, "Quartier")
    y += 20 * S
    field(d, x, y, hw, "Ville", "Abidjan")
    y = field(d, x + hw + 12 * S, y, hw, "Quartier", "Cocody") + 16 * S

    y = label(d, x, y, "Budget indicatif")
    field(d, x, y, hw, "Minimum", "150 000")
    y = field(d, x + hw + 12 * S, y, hw, "Maximum", "220 000") + 14 * S
    cx = x
    for lab, sel in [("Par heure", False), ("Par jour", False), ("Forfait", True)]:
        cx += chip(d, cx, y, lab, sel) + 8 * S
    y += 46 * S

    y = label(d, x, y, "Quand ?")
    cx = x
    for lab, sel in [("Urgent", False), ("Cette semaine", True),
                     ("Flexible", False)]:
        cx += chip(d, cx, y, lab, sel) + 8 * S
    y += 56 * S

    button(d, x, y, w, "Publier la demande")
    return img


def screen_applications():
    img, d = new_screen()
    app_bar(d, "Candidatures", back=True)

    d.rectangle([0, 84 * S, W, 148 * S], fill=WHITE)
    d.text((20 * S, 100 * S), "Construction mur de clôture", font=F("b", 15),
           fill=INK)
    d.text((20 * S, 124 * S), "Abidjan · Cocody · 4 candidatures",
           font=F("r", 12), fill=INK54)

    y = 160 * S
    for name, head, note, count, price, ago in [
        ("Ibrahim Traoré", "Maçon · 12 ans", 4.8, 23, "180 000 XOF", "il y a 2 h"),
        ("Seydou Coulibaly", "Maçon · carreleur", 4.2, 6, "165 000 XOF",
         "il y a 5 h"),
        ("Adama Konaté", "Maçon", 0, 0, "200 000 XOF", "il y a 1 j"),
        ("Bakary Sanogo", "Chef de chantier", 4.7, 14, "195 000 XOF",
         "il y a 2 j"),
    ]:
        h = 128 * S
        card(d, 12 * S, y, W - 24 * S, h)
        avatar(d, 12 * S + 40 * S, y + 40 * S, 26 * S, name[0])
        tx = 12 * S + 78 * S
        d.text((tx, y + 18 * S), name, font=F("m", 14), fill=INK)
        d.text((tx, y + 38 * S), head, font=F("r", 11), fill=INK54)
        rating(d, tx, y + 56 * S, note, count)
        d.text((W - 20 * S, y + 18 * S), price, font=F("b", 14), fill=PRIMARY,
               anchor="ra")
        d.text((W - 20 * S, y + 40 * S), ago, font=F("r", 10), fill=INK45,
               anchor="ra")
        bw = (W - 24 * S - 28 * S - 16 * S) / 3
        by = y + 78 * S
        button(d, 26 * S, by, bw, "Profil", filled=False, h=36)
        button(d, 26 * S + bw + 8 * S, by, bw, "Message", filled=False, h=36)
        button(d, 26 * S + 2 * (bw + 8 * S), by, bw, "Choisir", h=36)
        y += h + 10 * S

    return img


def screen_chat():
    img, d = new_screen()
    app_bar(d, "Ibrahim Traoré", back=True)

    msgs = [
        (False, "Bonjour, j'ai vu votre demande pour le mur de clôture.", "09:12"),
        (False, "Je suis disponible dès lundi.", "09:12"),
        (True, "Bonjour Ibrahim. Le terrain fait 18 m de long.", "09:20"),
        (True, "Vous fournissez les parpaings ?", "09:20"),
        (False, "Oui, fourniture comprise dans les 180 000.", "09:31"),
        (True, "Parfait, on part là-dessus.", "09:34"),
    ]
    y = 104 * S
    d.text((W / 2, y), "Aujourd'hui", font=F("r", 11), fill=INK45, anchor="ma")
    y += 30 * S
    for mine, text, hour in msgs:
        f = F("r", 13)
        maxw = W * 0.75 - 28 * S
        words, lines, cur = text.split(), [], ""
        for wd in words:
            t = f"{cur} {wd}".strip()
            if d.textlength(t, font=f) <= maxw:
                cur = t
            else:
                lines.append(cur)
                cur = wd
        lines.append(cur)
        tw = max(d.textlength(l, font=f) for l in lines)
        bw = tw + 28 * S
        bh = len(lines) * 22 * S + 34 * S
        bx = W - 16 * S - bw if mine else 16 * S
        fill = PRIMARY if mine else WHITE
        d.rounded_rectangle([bx, y, bx + bw, y + bh], 14 * S, fill=fill,
                            outline=None if mine else CARD_BORDER,
                            width=0 if mine else S)
        for i, l in enumerate(lines):
            d.text((bx + 14 * S, y + 12 * S + i * 22 * S), l, font=f,
                   fill=WHITE if mine else INK)
        d.text((bx + bw - 12 * S, y + bh - 18 * S), hour, font=F("r", 9),
               fill=(210, 226, 216) if mine else INK45, anchor="ra")
        y += bh + 10 * S

    iy = H - 76 * S
    d.rectangle([0, iy - 10 * S, W, H], fill=WHITE)
    d.rounded_rectangle([16 * S, iy, W - 72 * S, iy + 52 * S], 26 * S, fill=SURFACE,
                        outline=BORDER, width=S)
    d.text((34 * S, iy + 26 * S), "Écris ton message…", font=F("r", 13),
           fill=INK45, anchor="lm")
    d.ellipse([W - 62 * S, iy, W - 10 * S, iy + 52 * S], fill=PRIMARY)
    d.polygon([(W - 46 * S, iy + 16 * S), (W - 24 * S, iy + 26 * S),
               (W - 46 * S, iy + 36 * S)], fill=WHITE)
    return img


def screen_job_feed():
    img, d = new_screen()
    app_bar(d, "Missions disponibles")

    y = 96 * S
    x = 12 * S
    for lab, sel in [("Mes métiers", True), ("Urgent", False),
                     ("Cette semaine", False)]:
        x += chip(d, x, y, lab, sel) + 8 * S

    y += 48 * S
    for title, trade, place, budget, urg, ago in [
        ("Construction mur de clôture", "Maçon", "Cocody · 2,3 km",
         "150 000 – 220 000 XOF", "Cette semaine", "il y a 20 min"),
        ("Réfection installation électrique", "Électricien bâtiment",
         "Yopougon · 7,4 km", "80 000 – 120 000 XOF", "Urgent", "il y a 2 h"),
        ("Pose de carrelage 45 m²", "Carreleur", "Marcory · 4,1 km",
         "À négocier", "Flexible", "il y a 5 h"),
        ("Fuite sous évier", "Plombier", "Treichville · 9,2 km",
         "15 000 – 25 000 XOF", "Urgent", "il y a 1 j"),
    ]:
        h = 116 * S
        card(d, 12 * S, y, W - 24 * S, h)
        d.text((26 * S, y + 16 * S), title, font=F("m", 14), fill=INK)
        d.text((26 * S, y + 40 * S), f"{trade} · {place}", font=F("r", 11),
               fill=INK54)
        d.text((26 * S, y + 62 * S), budget, font=F("b", 13), fill=PRIMARY)
        col = (192, 57, 43) if urg == "Urgent" else INK54
        bg = (250, 226, 222) if urg == "Urgent" else (236, 240, 237)
        tw = d.textlength(urg, font=F("m", 10))
        d.rounded_rectangle([26 * S, y + 84 * S, 26 * S + tw + 20 * S,
                             y + 106 * S], 6 * S, fill=bg)
        d.text((36 * S, y + 95 * S), urg, font=F("m", 10), fill=col, anchor="lm")
        d.text((W - 26 * S, y + 18 * S), ago, font=F("r", 10), fill=INK45,
               anchor="ra")
        y += h + 10 * S

    bottom_nav(d, WORKER_TABS, 0)
    return img


def screen_wallet():
    img, d = new_screen()
    app_bar(d, "Mes crédits", back=True)

    d.rounded_rectangle([16 * S, 104 * S, W - 16 * S, 236 * S], 16 * S,
                        fill=PRIMARY)
    d.text((W / 2, 132 * S), "Solde disponible", font=F("r", 13),
           fill=(198, 219, 206), anchor="ma")
    d.text((W / 2, 158 * S), "24", font=F("b", 44), fill=WHITE, anchor="ma")
    d.text((W / 2, 208 * S), "crédits", font=F("m", 13), fill=(198, 219, 206),
           anchor="ma")

    y = 256 * S
    button(d, 20 * S, y, W - 40 * S, "Regarder une vidéo (+1 crédit)")
    y += 56 * S
    button(d, 20 * S, y, W - 40 * S, "Acheter des crédits (Mobile Money)",
           filled=False)

    y += 76 * S
    d.text((20 * S, y), "Historique", font=F("b", 15), fill=INK)
    y += 30 * S
    for lab, when, delta, pos in [
        ("Vidéo récompensée", "il y a 2 h", "+1", True),
        ("Contact débloqué · Awa K.", "il y a 6 h", "−2", False),
        ("Achat Mobile Money", "il y a 1 j", "+20", True),
        ("Contact débloqué · Bakary S.", "il y a 2 j", "−2", False),
        ("Bonus d'inscription", "il y a 5 j", "+5", True),
    ]:
        card(d, 12 * S, y, W - 24 * S, 60 * S, radius=12)
        d.text((26 * S, y + 14 * S), lab, font=F("m", 13), fill=INK)
        d.text((26 * S, y + 34 * S), when, font=F("r", 10), fill=INK45)
        d.text((W - 26 * S, y + 22 * S), delta, font=F("b", 15),
               fill=PRIMARY if pos else (192, 57, 43), anchor="ra")
        y += 68 * S

    return img


def screen_profile():
    img, d = new_screen()
    app_bar(d, "Mon compte")

    d.rectangle([0, 84 * S, W, 236 * S], fill=WHITE)
    avatar(d, W / 2, 140 * S, 38 * S, "A")
    d.text((W / 2, 190 * S), "Awa Kouassi", font=F("b", 17), fill=INK,
           anchor="ma")
    d.text((W / 2, 214 * S), "Abidjan · Cocody", font=F("r", 12), fill=INK54,
           anchor="ma")

    y = 252 * S
    for title, sub in [
        ("Langue", "Français"),
        ("Mes coordonnées", "Téléphone, WhatsApp, email, position"),
        ("Mes crédits", "24 crédits"),
        ("Mon profil ouvrier", "Métiers, tarifs, disponibilité"),
        ("Devenir ouvrier", "Recevoir des missions près de chez toi"),
    ]:
        card(d, 12 * S, y, W - 24 * S, 68 * S, radius=12)
        d.rounded_rectangle([26 * S, y + 18 * S, 58 * S, y + 50 * S], 8 * S,
                            fill=(232, 240, 235))
        d.text((72 * S, y + 16 * S), title, font=F("m", 14), fill=INK)
        d.text((72 * S, y + 38 * S), sub, font=F("r", 11), fill=INK54)
        cx, cy = W - 30 * S, y + 34 * S
        d.line([cx - 4 * S, cy - 6 * S, cx + 2 * S, cy, cx - 4 * S, cy + 6 * S],
               fill=INK45, width=int(1.6 * S), joint="curve")
        y += 76 * S

    y += 8 * S
    button(d, 20 * S, y, W - 40 * S, "Se déconnecter", filled=False)

    bottom_nav(d, CLIENT_TABS, 3)
    return img


SCREENS = [
    ("tel-01.png", screen_search),
    ("tel-02.png", screen_worker_detail),
    ("tel-03.png", screen_job_create),
    ("tel-04.png", screen_applications),
    ("tel-05.png", screen_chat),
    ("tel-06.png", screen_job_feed),
    ("tel-07.png", screen_wallet),
    ("tel-08.png", screen_profile),
]


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
    os.makedirs(out, exist_ok=True)
    for name, fn in SCREENS:
        path = os.path.join(out, name)
        fn().save(path, "PNG")
        print("écrit :", path)


if __name__ == "__main__":
    main()
