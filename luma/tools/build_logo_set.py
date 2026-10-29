#!/usr/bin/env python3
"""Glossy logo-only icon set for 300 charting apps, branded for metaPhasic Group.

Ranks 1–199 follow the Play topselling_free response. That response stops
before 300, so ranks 200–300 are the next US category Top Free apps that are
not already in the overall list. See research/us-top-free-300.json.
"""

from __future__ import annotations

import csv
import itertools
import json
import math
import re
import shutil
import subprocess
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from xml.etree import ElementTree as ET
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EXT = Path("/tmp/chart-extend.json")
OUT_JSON = ROOT / "research" / "us-top-free-300.json"
SVG_DIR = ROOT / "artwork" / "logo" / "svg"
PNG_DIR = ROOT / "artwork" / "logo" / "png" / "192"
PNG48 = ROOT / "artwork" / "logo" / "png" / "48"
DRAWABLE = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
XML_DIR = ROOT / "android" / "app" / "src" / "main" / "res" / "xml"
ASSETS = ROOT / "android" / "app" / "src" / "main" / "assets" / "dashboard"
DASH = ROOT / "dashboard"
BRAND = ROOT / "brand" / "metaphasic-group.png"
STORE = ROOT / "store"
TRACKER = ROOT / "tracker"

INK = "#243044"
PAPER = "#F7FBFF"

# Bottom color is saturated enough for a white glyph when the third flag is True.
PALETTES = [
    ("#E5F3FC", "#3E7CA8", True),
    ("#F4F1EA", "#C4A46A", False),
    ("#E5F6F1", "#2F8F78", True),
    ("#F0EAFB", "#6E59A8", True),
    ("#FBE8E4", "#C45B4E", True),
    ("#FBF3E2", "#C48A2A", False),
    ("#E7F0FC", "#3E6FAE", True),
    ("#E7F5FB", "#3E88A8", True),
]

CANDIDATES = {
    "com.whatsapp": ["com.whatsapp.Main"],
    "com.instagram.android": ["com.instagram.android.activity.MainTabActivity"],
    "com.facebook.katana": ["com.facebook.katana.LoginActivity"],
    "com.facebook.orca": ["com.facebook.orca.auth.StartScreenActivity"],
    "org.telegram.messenger": ["org.telegram.ui.LaunchActivity"],
    "com.zhiliaoapp.musically": ["com.ss.android.ugc.aweme.splash.SplashActivity"],
    "com.twitter.android": ["com.twitter.android.StartActivity"],
    "com.snapchat.android": ["com.snapchat.android.LandingPageActivity"],
}
SYSTEM_COMPONENTS = {
    "sys_phone": [
        "com.android.dialer/com.android.dialer.main.impl.MainActivity",
        "com.google.android.dialer/com.google.android.dialer.extensions.GoogleDialtactsActivity",
    ],
    "sys_messages": [
        "com.google.android.apps.messaging/com.google.android.apps.messaging.ui.ConversationListActivity",
        "com.android.messaging/com.android.messaging.ui.conversationlist.ConversationListActivity",
    ],
    "sys_camera": ["com.android.camera2/com.android.camera.CameraLauncher"],
    "sys_photos": ["com.google.android.apps.photos/com.google.android.apps.photos.home.HomeActivity"],
    "sys_settings": ["com.android.settings/com.android.settings.Settings"],
    "sys_clock": [
        "com.google.android.deskclock/com.android.deskclock.DeskClock",
        "com.android.deskclock/com.android.deskclock.DeskClock",
    ],
    "sys_calendar": ["com.google.android.calendar/com.android.calendar.AllInOneActivity"],
    "sys_browser": ["com.android.chrome/com.google.android.apps.chrome.Main"],
    "sys_calculator": [
        "com.google.android.calculator/com.android.calculator2.Calculator",
        "com.android.calculator2/com.android.calculator2.Calculator",
    ],
    "sys_contacts": [
        "com.google.android.contacts/com.android.contacts.activities.PeopleActivity",
        "com.android.contacts/com.android.contacts.activities.PeopleActivity",
    ],
    "sys_files": [
        "com.android.documentsui/com.android.documentsui.files.FilesActivity",
        "com.google.android.documentsui/com.android.documentsui.files.FilesActivity",
    ],
}

RULES = [
    (r"\bmuse\b", "spark"),
    (r"whatsapp|messenger|telegram|discord|signal|textnow|teams|chats?\b|sms|message", "bubble"),
    (r"gmail|outlook|mail\b|inbox", "mail"),
    (r"mapquest|google earth|\bmaps\b|waze|navigation|gps|life360", "pin"),
    (r"youtube|tiktok|netflix|hulu|tubi|peacock|capcut|reel|drama|video|movie|\btv\b", "play"),
    (r"bible|substack|youversion", "book"),
    (r"spotify|shazam|podcast|radio|\bmusic\b|audio", "note"),
    (r"camera|photo|gallery|picsart|lightroom", "camera"),
    (r"chrome|browser|firefox|\bedge\b", "compass"),
    (r"weather|forecast|\bradar\b", "cloud"),
    (r"calendar", "calendar"),
    (r"\bclock\b|alarm", "clock"),
    (r"clean|cleaner|storage|booster", "spark"),
    (r"volume|headphone|sound", "note"),
    (r"\bphone\b|dialer", "phone"),
    (r"walmart|amazon|temu|vinted|ebay|shop|cart|store|shein|target", "bag"),
    (r"paypal|venmo|cash app|capital one|bank|wallet|\bpay\b|finance", "card"),
    (r"mcdonald|doordash|ubereats|restaurant|coffee|food|starbucks", "cup"),
    (r"game|puzzle|merge|roblox|minecraft", "gamepad"),
    (r"fitness|workout|health|calm|strava", "heart"),
    (r"\bsettings\b", "spark"),
    (r"airbnb|zillow|realtor|\bhome\b|apartment", "house"),
    (r"chatgpt|claude|gemini|\bai\b|copilot", "spark"),
    (r"reddit|\bnews\b|cnn|\bbbc\b|nytimes|new york times", "news"),
    (r"crimeradar|dispatch", "news"),
    (r"duckduckgo", "compass"),
    (r"\bzoom\b", "bubble"),
    (r"recovery photo|photo recovery", "camera"),
    (r"spark driver", "car"),
    (r"block blast", "gamepad"),
    (r"indeed|linkedin|job|hiring", "briefcase"),
    (r"pdf|docs|office|notes|notion|evernote", "book"),
    (r"clean|cleaner|storage|booster", "spark"),
    (r"\bthreads\b", "bubble"),
    (r"instagram|snapchat|pinterest|photos", "camera"),
    (r"facebook", "people"),
    (r"(^|\s)x(\s|$)|twitter", "news"),
    (r"coupon|deal|discount|reward|freecash|\bearn\b|klarna|chase|wells|cash advance|grant", "card"),
    (r"kalshi|stock|trade|invest", "card"),
    (r"bible|substack", "book"),  # kept after the earlier bible rule; harmless if name already matched
    (r"paramount|disney|crunchyroll|roku|vizio|bigo|cine", "play"),
    (r"depop|costco|alibaba|wishlist", "bag"),
    (r"homescreen|launcher|theme|widget|ringtone|battery", "spark"),
    (r"headphone", "note"),
    (r"qr|barcode|scanner", "camera"),
    (r"translator", "book"),
    (r"okta|verify", "lock"),
    (r"pizza|burger|domino", "cup"),
    (r"transit|subway|\bbus\b", "pin"),
    (r"earnify", "card"),
    (r"\buber\b|\blyft\b", "car"),
    (r"airline|booking|expedia|delta|southwest|frontier|waymo|\bhotels?\b", "pin"),
    (r"trail|hike|run", "pin"),
    (r"mahjong", "gamepad"),
    (r"recipe|meal|planner", "cup"),
    (r"nextdoor|citizen|neighborhood", "house"),
    (r"keyboard", "calc"),
    (r"\bband\b|groups", "people"),
    (r"find hub|switch|move to ios", "phone"),
    (r"flo\b|ovulation|healow|mychart|period", "heart"),
    (r"drawing|artmate", "spark"),
    (r"adp|ukg|payroll", "briefcase"),
    (r"wakebox|timecue|reminder", "clock"),
    (r"triumph|\btcg\b|trading card", "card"),
    (r"t-life|tmobile|t-mobile", "phone"),
    (r"anime|playable", "play"),
    (r"navicore", "pin"),
    (r"rotate rings|maze|amaze|\barrows\b", "gamepad"),
    (r"deepstash", "book"),
    (r"kashkick|get paid", "card"),
    (r"\bsocial\b", "people"),
    (r"uber|lyft|drive", "car"),
    (r"duolingo|learn|education|study|class", "book"),
    (r"spotify", "note"),
    (r"translate|dictionary", "book"),
    (r"calculator", "calc"),
    (r"file|document|drive", "folder"),
    (r"security|authenticator|password|\bvpn\b|\block\b", "lock"),
    (r"dating|tinder|bumble|hinge", "heart"),
    (r"sport|espn|nfl|nba|score", "trophy"),
    (r"browser", "compass"),
]


def seed_of(package: str) -> int:
    value = 2166136261
    for char in package:
        value ^= ord(char)
        value = (value * 16777619) & 0xFFFFFFFF
    return value


def family_for(name: str, package: str) -> str:
    # Name first, so a package id cannot override the words on the icon label.
    for text in (name.lower(), f"{name} {package}".lower()):
        for pattern, family in RULES:
            if re.search(pattern, text):
                return family
    return "mark"


def circle(cx, cy, r, fill) -> str:
    return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}"/>'


def rect(x, y, w, h, rx, fill) -> str:
    return (
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
        f'rx="{rx:.1f}" fill="{fill}"/>'
    )


def path(d, fill) -> str:
    return f'<path d="{d}" fill="{fill}"/>'


def ring(cx, cy, outer, inner, fill) -> str:
    d = (
        f"M{cx-outer:.1f} {cy:.1f} a{outer:.1f} {outer:.1f} 0 1 0 {2*outer:.1f} 0 "
        f"a{outer:.1f} {outer:.1f} 0 1 0 {-2*outer:.1f} 0 "
        f"M{cx-inner:.1f} {cy:.1f} a{inner:.1f} {inner:.1f} 0 1 1 {2*inner:.1f} 0 "
        f"a{inner:.1f} {inner:.1f} 0 1 1 {-2*inner:.1f} 0"
    )
    return f'<path d="{d}" fill="{fill}" fill-rule="evenodd"/>'


def ellipse(cx, cy, rx, ry, fill) -> str:
    return f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"/>'


def glyph_note(fill: str, seed: int) -> str:
    kind = seed % 5
    head = 12 + (seed // 5) % 4
    stem = 36 + (seed // 20) % 4 * 3
    cx, cy = 84, 118
    parts = [ellipse(cx, cy, head, head * 0.72, fill), rect(cx + head - 4, cy - stem, 6, stem, 2, fill)]
    if kind == 0:
        parts.append(path(f"M{cx+head+2:.0f} {cy-stem:.0f} C{cx+head+28:.0f} {cy-stem+6:.0f} {cx+head+24:.0f} {cy-stem+22:.0f} {cx+head+2:.0f} {cy-stem+16:.0f} Z", fill))
    elif kind == 1:
        parts.append(path(f"M{cx-6:.0f} {cy:.0f} C{cx-28:.0f} {cy-8:.0f} {cx-24:.0f} {cy-28:.0f} {cx-4:.0f} {cy-18:.0f} Z", fill))
    elif kind == 2:
        parts.append(ellipse(cx + 28, cy + 6, head * 0.85, head * 0.6, fill))
        parts.append(rect(cx + head - 4, cy - stem, 34, 6, 2, fill))
    elif kind == 3:
        parts.append(circle(cx + 22, cy - stem + 8, 5, fill))
    else:
        parts.append(rect(cx + 8, cy - 6, 16, 5, 2, fill))
    return "\n".join(parts)


def glyph_camera(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    wide = 72 + a * 2
    top = 74 + b
    lens = 14 + c
    return "\n".join([
        rect(96 - wide / 2, top, wide, 54, 12, fill),
        rect(84 + c, top - 14, 22 + a, 16, 5, fill),
        ring(96, top + 28, lens, max(6, lens - 8), fill),
    ])


def glyph_clock(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    radius = 30 + c
    hands = [
        f"M94 {100-radius+6:.0f} H102 V104 L{112+a:.0f} {112+b:.0f} L{106+a:.0f} {122+b:.0f} L90 106 Z",
        f"M92 {100-radius+8:.0f} H100 V112 L{118+a:.0f} {98+b:.0f} L{114+a:.0f} {90+b:.0f} L96 100 Z",
        f"M94 {100-radius+4:.0f} H102 V100 L{78-a:.0f} {114+b:.0f} L{74-a:.0f} {106+b:.0f} L94 96 Z",
        f"M96 {100-radius+4:.0f} V108 H{116+a:.0f} V100 H104 V{100-radius+4:.0f} Z",
    ]
    return ring(96, 100, radius, radius - 8, fill) + path(hands[seed % 4], fill)


def glyph_bubble(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    w = 64 + a * 2
    h = 44 + c * 2
    top = 62 + b
    tails = [
        f"M{96-w/4:.0f} {top+h:.0f} L{96-w/4+8:.0f} {top+h+18:.0f} L{96:.0f} {top+h:.0f} Z",
        f"M{96:.0f} {top+h:.0f} L{96+w/5:.0f} {top+h+16:.0f} L{96+w/4:.0f} {top+h:.0f} Z",
        f"M{96-w/3:.0f} {top+h-4:.0f} L{96-w/3-8:.0f} {top+h+16:.0f} L{96-w/6:.0f} {top+h:.0f} Z",
        f"M{96+w/6:.0f} {top+h:.0f} L{96+w/3:.0f} {top+h+16:.0f} L{96+w/5:.0f} {top+h:.0f} Z",
    ]
    return rect(96 - w / 2, top, w, h, 18, fill) + path(tails[c % 4], fill)


def glyph_mail(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    x = 54 + a
    y = 70 + b
    w = 78 - c
    flap = x + w * (0.42 + (c % 3) * 0.06)
    return rect(x, y, w, 54, 8, fill) + path(
        f"M{x:.0f} {y+4:.0f} L{flap:.0f} {y+30:.0f} L{x+w:.0f} {y+4:.0f} L{x+w-12:.0f} {y+4:.0f} L{flap:.0f} {y+22:.0f} L{x+12:.0f} {y+4:.0f} Z",
        PAPER,
    )


def glyph_cloud(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    parts = []
    if a % 2 == 0:
        parts.append(circle(74 + c, 80 + b, 12 + c, fill))
    parts.append(path(
        f"M{68+a} {116+b} H{124-c} C{136-c} {116+b} {138-c} {100+b} {126-c} {98+b} "
        f"H{122-c} C{124-c} {82+b} {106} {76+b} {98} {88+b} C{92} {78+b} {76+a} {82+b} {76+a} {94+b} "
        f"C{62+a} {94+b} {60+a} {116+b} {68+a} {116+b} Z",
        fill,
    ))
    return "\n".join(parts)


def glyph_compass(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    radius = 30 + c
    needles = [
        f"M96 {100-radius+4:.0f} L{108+a:.0f} {108+b:.0f} L96 100 L{84-a:.0f} {108+b:.0f} Z",
        f"M96 {100-radius+8:.0f} L{114+a:.0f} {114+b:.0f} L96 102 L{78-a:.0f} {114+b:.0f} Z",
        f"M96 {100-radius+2:.0f} L{104+a:.0f} 96 L96 {100+radius-4:.0f} L{88-a:.0f} 96 Z",
    ]
    return ring(96, 100, radius, radius - 8, fill) + path(needles[b % 3], fill)


def glyph_calendar(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    rings = 2 + (c % 2)
    x = 52 + a
    y = 66 + b
    w = 84 - a
    parts = [rect(x, y, w, 66, 12, fill), rect(x, y, w, 18, 8, fill)]
    gap = (w - 24) / max(rings - 1, 1)
    for index in range(rings):
        parts.append(rect(x + 16 + index * gap, y - 12, 8, 20, 3, fill))
    return "\n".join(parts)


def glyph_phone(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    return path(
        f"M{68+a} {82+b} C{68+a} {66+b} {86+c} {58+b} {98+c} {70+b} "
        f"L{108+c} {84+b} C{100+c} {92+b} {100+a} {106+b} {114+a} {114+b} "
        f"L{126+a} {122+b} C{138+a} {130+b} {130+c} {146+b} {114+c} {140+b} "
        f"C{80+a} {130+b} {60+a} {104+b} {68+a} {82+b} Z",
        fill,
    )


def glyph_pin(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    r = 22 + c
    tip = 136 + b
    cy = 78 + a
    return (
        path(
            f"M96 {tip:.0f} C96 {tip:.0f} {96-r-6:.0f} {cy+22:.0f} {96-r-6:.0f} {cy:.0f} "
            f"A{r+6:.0f} {r+6:.0f} 0 1 1 {96+r+6:.0f} {cy:.0f} "
            f"C{96+r+6:.0f} {cy+22:.0f} 96 {tip:.0f} 96 {tip:.0f} Z",
            fill,
        )
        + circle(96, cy, 7 + c % 2, PAPER)
    )


def glyph_bag(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    w = 52 + a * 2
    top = 82 + b
    return rect(96 - w / 2, top, w, 50, 10, fill) + (
        f'<path d="M{96-w/4:.0f} {top:.0f} C{96-w/4:.0f} {top-22-c:.0f} {96+w/4:.0f} {top-22-c:.0f} {96+w/4:.0f} {top:.0f}" '
        f'fill="none" stroke="{fill}" stroke-width="8" stroke-linecap="round"/>'
    )


def glyph_play(fill: str, seed: int) -> str:
    left = 70 + (seed % 7) * 2
    top = 62 + ((seed // 7) % 6) * 2
    height = 50 + ((seed // 42) % 6) * 3
    right = left + 46 + ((seed // 252) % 5) * 3
    mid = top + height / 2
    tri = f"M{left:.0f} {top:.0f} L{left:.0f} {top+height:.0f} L{right:.0f} {mid:.0f} Z"
    mode = (seed // 11) % 3
    if mode == 0:
        return path(tri, fill)
    if mode == 1:
        return rect(left - 16, top - 10, (right - left) + 30, height + 20, 16, fill) + path(
            f"M{left:.0f} {top+6:.0f} L{left:.0f} {top+height-6:.0f} L{right-8:.0f} {mid:.0f} Z",
            PAPER,
        )
    return ring(96, 100, 36, 28, fill) + path(tri, fill)


def dims(seed: int) -> tuple[int, int, int]:
    return seed % 9, (seed // 9) % 7, (seed // 63) % 5


def glyph_heart(fill: str, seed: int) -> str:
    a, b, _c = dims(seed)
    left = 60 + a
    right = 132 - a
    top = 54 + b
    return path(
        f"M96 130 C96 130 {left} 106 {left} {top+24} C{left} {top} {left+14} {top-8} {left+26} {top-8} "
        f"C{96-6} {top-8} 96 {top-2} 96 {top+4} C96 {top-2} {96+6} {top-8} {right-26} {top-8} "
        f"C{right-14} {top-8} {right} {top} {right} {top+24} C{right} 106 96 130 96 130 Z",
        fill,
    )


def glyph_house(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    door = 12 + c * 2
    roof = 56 + b
    return path(f"M96 {roof} L{142-a} 98 H{126-a} V136 H{66+a} V98 H{50+a} Z", fill) + rect(
        96 - door / 2, 112, door, 24, 2, PAPER
    )


def glyph_spark(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    outer = 26 + a
    inner = 8 + c
    pts = []
    points = 8 if b % 2 == 0 else 12
    for i in range(points):
        ang = -math.pi / 2 + i * math.pi / (points / 2)
        radius = outer if i % 2 == 0 else inner
        pts.append(f"{96 + radius * math.cos(ang):.1f} {100 + radius * math.sin(ang):.1f}")
    return path("M " + " L ".join(pts) + " Z", fill)


def glyph_news(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    lines = 3 + c % 2
    width = 72 + a
    parts = [rect(96 - width / 2, 58 + b, width, 78, 8, fill)]
    for index in range(lines):
        parts.append(rect(96 - width / 2 + 12, 74 + b + index * 14, width - 28 - (index % 2) * 10, 6, 2, PAPER))
    return "\n".join(parts)


def glyph_briefcase(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    return (
        rect(54 + a, 78 + b, 80 - a, 52, 8, fill)
        + rect(78 + c, 64 + b, 36 - c, 16, 4, fill)
        + rect(54 + a, 98 + b, 80 - a, 6, 1, PAPER)
    )


def glyph_book(fill: str, seed: int) -> str:
    a, _b, c = dims(seed)
    lean = a - 4
    top = 66 + c
    return (
        path(f"M96 {top+8} L{62+lean:.0f} {top} L{62+lean:.0f} {top+56} L96 {top+64} Z", fill)
        + path(f"M96 {top+8} L{130-lean:.0f} {top} L{130-lean:.0f} {top+56} L96 {top+64} Z", fill)
    )


def glyph_gamepad(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    return (
        rect(54 + a, 76 + b, 84 - a, 46, 16 + c, fill)
        + circle(74 + c, 98 + b, 5, PAPER)
        + circle(112 + a, 92 + b, 4, PAPER)
        + circle(112 + a, 108 + b, 4, PAPER)
    )


def glyph_cup(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    left = 72 + a
    right = 116 - c
    return (
        path(f"M{left} {78+b} H{right} L{right-6} {126+b} H{left+6} Z", fill)
        + ellipse((left + right) / 2, 78 + b, 20, 7, fill)
        + rect(right - 6, 56 + c, 6, 26, 3, fill)
    )


def glyph_card(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    x = 52 + a
    y = 70 + b
    w = 84 - c
    return rect(x, y, w, 54, 8, fill) + rect(x, y + 14, w, 8, 0, PAPER) + rect(x + 12, y + 32, 18 + c, 6, 2, PAPER)


def glyph_people(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    head = 12 + c
    return circle(96 + a - 4, 76 + b, head, fill) + path(
        f"M{62+a} 134 C{66+a} {102+b} {126-a} {102+b} {130-a} 134 Z", fill
    )


def glyph_car(fill: str, seed: int) -> str:
    a, b, _c = dims(seed)
    return (
        path(f"M{62+a} {108+b} L{76+a} {86+b} H{116-a} L{130-a} {108+b} Z", fill)
        + rect(58 + a, 106 + b, 78 - a, 18, 6, fill)
        + circle(78 + a, 128 + b, 7, fill)
        + circle(118 - a, 128 + b, 7, fill)
    )


def glyph_lock(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    return rect(66 + a, 94 + b, 56 - c, 42, 8, fill) + (
        f'<path d="M{76+a} {94+b} V{82+b} A{14+c} {14+c} 0 0 1 {112-c} {82+b} V{94+b}" '
        f'fill="none" stroke="{fill}" stroke-width="8"/>'
    )


def glyph_folder(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    return path(
        f"M{54+a} {76+b} H{86+c} L{98+c} {88+b} H{138-a} V{132+b} H{54+a} Z",
        fill,
    )


def glyph_calc(fill: str, seed: int) -> str:
    a, b, c = dims(seed)
    parts = [rect(60 + a, 56 + b, 70, 82, 12, fill), rect(72 + a, 68 + b, 46, 14, 3, PAPER)]
    for index in range(3):
        parts.append(circle(78 + a + index * 16, 102 + b + c, 4, PAPER))
    return "\n".join(parts)


def glyph_trophy(fill: str, seed: int) -> str:
    a, b, _c = dims(seed)
    return (
        path(f"M{76+a} {62+b} H{116-a} V{90+b} C{116-a} {108+b} {76+a} {108+b} {76+a} {90+b} Z", fill)
        + rect(90, 104 + b, 12, 16, 2, fill)
        + rect(76 + a, 120 + b, 40 - a, 8, 3, fill)
    )


def connected_shapes() -> list[tuple[tuple[int, int], ...]]:
    cells = [(x, y) for y in range(3) for x in range(3)]

    def linked(group: tuple[tuple[int, int], ...]) -> bool:
        remain = set(group)
        stack = [group[0]]
        seen = {group[0]}
        while stack:
            x, y = stack.pop()
            for nxt in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if nxt in remain and nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        return len(seen) == len(group)

    shapes = []
    for size in (5, 4, 6, 3):
        for combo in itertools.combinations(cells, size):
            if linked(combo):
                shapes.append(tuple(sorted(combo)))
    # Stable and unique.
    unique = []
    seen = set()
    for shape in shapes:
        if shape not in seen:
            seen.add(shape)
            unique.append(shape)
    return unique


SHAPES = connected_shapes()


def glyph_mark(fill: str, seed: int) -> str:
    shape = SHAPES[seed % len(SHAPES)]
    cx = sum(x for x, _ in shape) / len(shape)
    cy = sum(y for _, y in shape) / len(shape)
    parts = []
    spread = 24
    radius = 16
    for x, y in shape:
        parts.append(circle(96 + (x - cx) * spread, 100 + (y - cy) * spread, radius, fill))
    return "\n".join(parts)


GLYPHS = {
    "note": glyph_note,
    "camera": glyph_camera,
    "clock": glyph_clock,
    "bubble": glyph_bubble,
    "mail": glyph_mail,
    "cloud": glyph_cloud,
    "compass": glyph_compass,
    "calendar": glyph_calendar,
    "phone": glyph_phone,
    "pin": glyph_pin,
    "bag": glyph_bag,
    "play": glyph_play,
    "heart": glyph_heart,
    "house": glyph_house,
    "spark": glyph_spark,
    "news": glyph_news,
    "briefcase": glyph_briefcase,
    "book": glyph_book,
    "gamepad": glyph_gamepad,
    "cup": glyph_cup,
    "card": glyph_card,
    "people": glyph_people,
    "car": glyph_car,
    "lock": glyph_lock,
    "folder": glyph_folder,
    "calc": glyph_calc,
    "trophy": glyph_trophy,
    "mark": glyph_mark,
}


def tile_svg(slug: str, palette_index: int, glyph: str) -> str:
    top, bottom, _white = PALETTES[palette_index % len(PALETTES)]
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <defs>
    <linearGradient id="{slug}bg" x1="40" y1="18" x2="150" y2="176" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{top}"/>
      <stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
    <linearGradient id="{slug}glass" x1="96" y1="16" x2="96" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.7"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="{slug}clip"><rect x="18" y="18" width="156" height="156" rx="46"/></clipPath>
  </defs>
  <rect x="18" y="18" width="156" height="156" rx="46" fill="url(#{slug}bg)"/>
  <g clip-path="url(#{slug}clip)">
    <ellipse cx="78" cy="58" rx="58" ry="32" fill="#ffffff" fill-opacity="0.28"/>
    <path d="M34 84C52 46 84 30 112 32c-26 4-56 26-72 58-6 12-10 24-10 32 0-14 2-28 4-38z" fill="url(#{slug}glass)"/>
  </g>
  <rect x="19" y="19" width="154" height="154" rx="45" fill="none" stroke="#ffffff" stroke-opacity="0.8" stroke-width="1.5"/>
  {glyph}
</svg>
'''


def build_chart() -> list[dict]:
    payload = json.loads(EXT.read_text(encoding="utf-8"))
    overall = payload["overall"]
    seen = {app["appId"] for app in overall}
    best = {}
    for row in payload["extra"]:
        if row["appId"] in seen:
            continue
        current = best.get(row["appId"])
        key = (row["categoryRank"], row["category"], row["appId"])
        if current is None or key < (current["categoryRank"], current["category"], current["appId"]):
            best[row["appId"]] = row
    extension = sorted(best.values(), key=lambda row: (row["categoryRank"], row["category"], row["appId"]))
    apps = []
    for index, app in enumerate(overall, start=1):
        apps.append(
            {
                "rank": index,
                "name": app["title"],
                "packageId": app["appId"],
                "developer": app.get("developer") or "",
                "score": app.get("score"),
                "list": "overall",
                "category": "",
                "categoryRank": "",
            }
        )
    for row in extension:
        if len(apps) >= 300:
            break
        apps.append(
            {
                "rank": len(apps) + 1,
                "name": row["title"],
                "packageId": row["appId"],
                "developer": row.get("developer") or "",
                "score": row.get("score"),
                "list": "category",
                "category": row["category"],
                "categoryRank": row["categoryRank"],
            }
        )
    if len(apps) < 300:
        raise SystemExit(f"only assembled {len(apps)} apps")
    ids = [app["packageId"] for app in apps]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate package in the 300")
    fetched = datetime.fromisoformat(payload["fetchedAt"].replace("Z", "+00:00")).astimezone(
        ZoneInfo("America/Los_Angeles")
    )
    document = {
        "target": 300,
        "count": 300,
        "fetchedAt": payload["fetchedAt"],
        "fetchedAtPacific": fetched.strftime("%Y-%m-%d %I:%M %p PT"),
        "overall": {
            "source": "google-play-scraper list TOP_FREE category=APPLICATION country=us lang=en",
            "returned": len(overall),
            "note": "The Play topselling_free response returned 199 apps when more were requested. Ranks 1-199 are that order.",
        },
        "extension": {
            "note": (
                "Ranks 200-300 are additional apps from US category Top Free charts fetched in the same session, "
                "after removing every package already in the overall 199. Order is best category rank, then category name. "
                "They are charting free apps. They are not an official overall rank, because this Play response does not publish ranks 200-300."
            ),
            "categoriesFetched": sorted({row["category"] for row in payload["extra"]}),
        },
        "apps": apps,
    }
    OUT_JSON.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return apps


def drawable_name(rank: int) -> str:
    return f"g{rank:03d}"


def check_icon(png: Path, slug: str) -> None:
    image = Image.open(png).convert("RGBA")
    if image.size != (192, 192):
        raise SystemExit(f"{slug} size {image.size}")
    if image.getpixel((0, 0))[3] != 0 or image.getpixel((191, 0))[3] != 0:
        raise SystemExit(f"{slug} corners are not transparent")
    if image.getpixel((96, 96))[3] < 250:
        raise SystemExit(f"{slug} center is transparent")
    small = image.resize((48, 48), Image.Resampling.LANCZOS)
    pixels = small.load()
    # Background sample from inside the tile, away from the glyph center.
    bg = pixels[24, 10]
    marks = []
    for y in range(48):
        for x in range(48):
            r, g, b, a = pixels[x, y]
            if a < 220:
                continue
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 70:
                marks.append((x, y))
    if len(marks) < 36:
        raise SystemExit(f"{slug} glyph is too faint at 48px ({len(marks)})")
    xs = [p[0] for p in marks]
    ys = [p[1] for p in marks]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    if max(max(xs) - min(xs), max(ys) - min(ys)) < 12:
        raise SystemExit(f"{slug} glyph is tiny")
    if abs(cx - 23.5) > 8 or abs(cy - 23.5) > 8:
        raise SystemExit(f"{slug} off center {cx:.1f},{cy:.1f}")


def write_mappings(apps: list[dict]) -> int:
    by_package = {app["packageId"]: app for app in apps}
    lines = []
    mapped = 0
    for package, activities in CANDIDATES.items():
        app = by_package.get(package)
        if not app:
            continue
        drawable = drawable_name(app["rank"])
        for activity in activities:
            lines.append(
                f'    <item component="ComponentInfo{{{package}/{activity}}}" drawable="{drawable}"/>'
            )
            mapped += 1
    for drawable, components in SYSTEM_COMPONENTS.items():
        for component in components:
            lines.append(
                f'    <item component="ComponentInfo{{{component}}}" drawable="{drawable}"/>'
            )
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- PROTOTYPE. Logo-set mappings are unverified. No launcher was tested. -->\n"
        "<resources>\n"
        '    <iconback img1="iconback"/>\n'
        '    <iconmask img1="iconmask"/>\n'
        '    <iconupon img1="iconupon"/>\n'
        '    <scale factor="1.0"/>\n'
        + "\n".join(lines)
        + "\n</resources>\n"
    )
    (XML_DIR / "appfilter.xml").write_text(xml, encoding="utf-8")
    draw_items = ['    <category title="Luma logo set"/>']
    for app in apps:
        draw_items.append(f'    <item drawable="{drawable_name(app["rank"])}"/>')
    draw_items.append('    <category title="Ink study and system"/>')
    ink = sorted(path.stem for path in (ROOT / "artwork" / "svg").glob("*.svg"))
    for name in ink:
        if name.startswith("icon"):
            continue
        draw_items.append(f'    <item drawable="{name}"/>')
    drawable_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n" + "\n".join(draw_items) + "\n</resources>\n"
    )
    (XML_DIR / "drawable.xml").write_text(drawable_xml, encoding="utf-8")
    appmap = ['<?xml version="1.0" encoding="utf-8"?>', "<!-- PROTOTYPE. Unverified activities. -->", "<appmap>"]
    for package, activities in CANDIDATES.items():
        app = by_package.get(package)
        if not app:
            continue
        for activity in activities:
            appmap.append(f'    <item class="{activity}" name="{drawable_name(app["rank"])}"/>')
    appmap.append("</appmap>\n")
    (XML_DIR / "appmap.xml").write_text("\n".join(appmap), encoding="utf-8")
    for name in ("appfilter.xml", "drawable.xml", "appmap.xml"):
        ET.parse(XML_DIR / name)
    return mapped


def dashboard(apps: list[dict], asset_prefix: str, brand_src: str) -> str:
    cards = []
    for app in apps:
        source = "Overall Top Free" if app["list"] == "overall" else f"{app['category']} #{app['categoryRank']}"
        cards.append(
            f'''<figure class="icon">
  <img src="{asset_prefix}{drawable_name(app["rank"])}.png" width="92" height="92" alt="{escape(app["name"])}"/>
  <figcaption>
    <strong>{escape(app["name"][:42])}</strong>
    <span>#{app["rank"]} · {escape(source)}</span>
    <span class="pkg">{escape(app["packageId"])}</span>
  </figcaption>
</figure>'''
        )
    grid = "\n".join(cards)
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Luma — metaPhasic Group</title>
  <style>
    :root {{ color-scheme: light; }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "Segoe UI", Helvetica, Arial, sans-serif;
      color: #243044;
      background: #e7eef4;
    }}
    .brandbar {{
      display: flex;
      gap: 28px;
      align-items: center;
      padding: 28px 40px;
      background: #2a2d34;
      color: white;
    }}
    .brandbar img {{
      width: 280px;
      height: auto;
      display: block;
    }}
    h1 {{
      margin: 0;
      font-weight: 560;
      font-size: 48px;
      letter-spacing: -0.045em;
    }}
    .tag {{ margin: 4px 0 0; color: #d5dde6; font-size: 18px; }}
    .status {{
      display: inline-block;
      margin-top: 12px;
      border: 1px solid rgba(255,255,255,0.35);
      border-radius: 999px;
      padding: 5px 10px;
      font-size: 12px;
      letter-spacing: 0.08em;
    }}
    .metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      padding: 18px 40px 0;
    }}
    .metric {{
      background: white;
      border-radius: 16px;
      padding: 12px 14px;
    }}
    .metric b {{ display: block; font-size: 26px; letter-spacing: -0.04em; }}
    .metric span {{ color: #5c6b7c; font-size: 13px; }}
    section {{ padding: 8px 40px 32px; }}
    h2 {{ font-size: 18px; margin: 22px 0 8px; }}
    p.note {{ color: #5c6b7c; margin: 0 0 14px; max-width: 70ch; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
      gap: 12px;
    }}
    figure.icon {{
      margin: 0;
      background: rgba(255,255,255,0.76);
      border-radius: 18px;
      padding: 12px 8px 10px;
      text-align: center;
    }}
    figure img {{
      width: 92px;
      height: 92px;
      filter: drop-shadow(0 8px 10px rgba(36,48,68,0.16));
    }}
    figcaption {{ display: flex; flex-direction: column; gap: 2px; }}
    figcaption strong {{ font-size: 13px; }}
    figcaption span {{ color: #5c6b7c; font-size: 11px; }}
    .pkg {{ font-family: ui-monospace, monospace; word-break: break-all; }}
    @media (max-width: 720px) {{
      .brandbar {{ flex-direction: column; align-items: flex-start; padding: 20px; }}
      .brandbar img {{ width: min(100%, 280px); }}
      .metrics {{ grid-template-columns: 1fr 1fr; padding: 16px 20px 0; }}
      section {{ padding: 8px 20px 28px; }}
    }}
  </style>
</head>
<body>
  <header class="brandbar">
    <img src="{brand_src}" alt="metaPhasic Group"/>
    <div>
      <h1>Luma</h1>
      <p class="tag">Your home screen, considered.</p>
      <div class="status">LOGO SET · PROTOTYPE</div>
    </div>
  </header>
  <div class="metrics">
    <div class="metric"><b>300</b><span>logo-only icons</span></div>
    <div class="metric"><b>199</b><span>overall Top Free ranks</span></div>
    <div class="metric"><b>101</b><span>category-chart continuation</span></div>
    <div class="metric"><b>0</b><span>launcher tests</span></div>
  </div>
  <section>
    <h2>Logo set</h2>
    <p class="note">One symbol on a luminous squircle, in the spirit of a single-glyph music icon: no wordmark on the tile. Symbols are original interpretations, not official app artwork. Ranks 1–199 are the US Play Top Free response. Ranks 200–300 continue with category Top Free apps because that overall response stops at 199.</p>
    <div class="grid">
      {grid}
    </div>
  </section>
</body>
</html>
'''


def feature_graphic(apps: list[dict]) -> None:
    canvas = Image.new("RGB", (1024, 500), (42, 45, 52))
    logo = Image.open(BRAND).convert("RGBA")
    logo.thumbnail((460, 220), Image.Resampling.LANCZOS)
    canvas.paste(logo, (40, 40), logo)
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 28)
    small = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
    draw = ImageDraw.Draw(canvas)
    draw.text((48, 300), "Luma  ·  logo set", fill=(255, 255, 255), font=font)
    draw.text((48, 348), "300 single-glyph icons", fill=(213, 221, 230), font=small)
    draw.text((48, 382), "Prototype, not a Play release", fill=(232, 160, 150), font=small)
    picks = [apps[i] for i in (0, 1, 6, 11, 20, 40)]
    for index, app in enumerate(picks):
        icon = Image.open(PNG_DIR / f"{drawable_name(app['rank'])}.png").convert("RGBA")
        icon = icon.resize((120, 120), Image.Resampling.LANCZOS)
        canvas.paste(icon, (560 + (index % 3) * 140, 70 + (index // 3) * 150), icon)
    canvas.save(STORE / "feature-graphic-1024x500.png", "PNG")


def main() -> None:
    apps = build_chart()
    for folder in (SVG_DIR, PNG_DIR, PNG48):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    geometries = {}
    family_counts = {}
    for app in apps:
        family = family_for(app["name"], app["packageId"])
        family_counts[family] = family_counts.get(family, 0) + 1
        # Mark tiles cycle a dedicated seed so connected shapes spread out.
        base_seed = seed_of(app["packageId"]) + app["rank"] * 131
        slug = drawable_name(app["rank"])
        glyph = ""
        for attempt in range(40):
            glyph_seed = base_seed + attempt * 17 + (app["rank"] if family == "mark" else 0)
            glyph = GLYPHS[family](INK, glyph_seed)
            if glyph not in geometries:
                break
        else:
            raise SystemExit(f"could not uniquify {slug} family {family}")
        geometries[glyph] = slug
        svg = tile_svg(slug, app["rank"] - 1, glyph)
        svg_path = SVG_DIR / f"{slug}.svg"
        png_path = PNG_DIR / f"{slug}.png"
        svg_path.write_text(svg, encoding="utf-8")
        subprocess.run(
            ["rsvg-convert", "-w", "192", "-h", "192", "-o", str(png_path), str(svg_path)],
            check=True,
        )
        subprocess.run(
            ["rsvg-convert", "-w", "48", "-h", "48", "-o", str(PNG48 / f"{slug}.png"), str(svg_path)],
            check=True,
        )
        check_icon(png_path, slug)
        shutil.copyfile(png_path, DRAWABLE / f"{slug}.png")
        app["family"] = family
        app["drawable"] = slug

    mapped = write_mappings(apps)
    asset_icons = ASSETS / "logo"
    if asset_icons.exists():
        shutil.rmtree(asset_icons)
    asset_icons.mkdir(parents=True)
    brand_asset = ASSETS / "brand"
    brand_asset.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(BRAND, brand_asset / "metaphasic-group.png")
    for app in apps:
        shutil.copyfile(PNG_DIR / f"{app['drawable']}.png", asset_icons / f"{app['drawable']}.png")
    (ASSETS / "index.html").write_text(
        dashboard(apps, "logo/", "brand/metaphasic-group.png"),
        encoding="utf-8",
    )
    (DASH / "index.html").write_text(
        dashboard(apps, "../artwork/logo/png/192/", "../brand/metaphasic-group.png"),
        encoding="utf-8",
    )
    feature_graphic(apps)

    with (TRACKER / "logo-progress.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "rank", "name", "package_id", "list", "category", "category_rank",
                "family", "drawable", "artwork", "mapping_verified", "launcher_tested",
                "counts_as_app_coverage",
            ],
        )
        writer.writeheader()
        for app in apps:
            writer.writerow(
                {
                    "rank": app["rank"],
                    "name": app["name"],
                    "package_id": app["packageId"],
                    "list": app["list"],
                    "category": app["category"],
                    "category_rank": app["categoryRank"],
                    "family": app["family"],
                    "drawable": app["drawable"],
                    "artwork": "prototype",
                    "mapping_verified": "false",
                    "launcher_tested": "false",
                    "counts_as_app_coverage": "true",
                }
            )
    summary = {
        "set": "logo",
        "status": "prototype",
        "release_ready": False,
        "icons": 300,
        "overall_ranks": 199,
        "category_continuation": 101,
        "families": family_counts,
        "candidate_mapping_lines": mapped,
        "mapping_verified": 0,
        "launcher_tested": 0,
        "brand": "metaPhasic Group",
    }
    (TRACKER / "logo-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
