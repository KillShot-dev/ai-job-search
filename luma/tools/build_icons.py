#!/usr/bin/env python3
"""Build Luma's prototype vector masters, PNG exports, mappings, and dashboard.

Glyph geometry is the source of the icon art. The script refuses to emit a
generic fallback in place of a missing glyph, and it checks every app icon
against the recorded Play snapshot.
"""

from __future__ import annotations

import csv
import json
import math
import shutil
import subprocess
from html import escape
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "research" / "us-top-free-snapshot.json"
SVG_DIR = ROOT / "artwork" / "svg"
PNG_DIR = ROOT / "artwork" / "png" / "192"
PNG48_DIR = ROOT / "artwork" / "png" / "48"
PREVIEW = ROOT / "artwork" / "preview"
DRAWABLE = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
XML_DIR = ROOT / "android" / "app" / "src" / "main" / "res" / "xml"
VALUES = ROOT / "android" / "app" / "src" / "main" / "res" / "values"
ASSETS = ROOT / "android" / "app" / "src" / "main" / "assets" / "dashboard"
DASH = ROOT / "dashboard"
STORE = ROOT / "store"
TRACKER = ROOT / "tracker"

INK = "#243044"
PAPER = "#F7FBFF"
PLATES = [
    ("#F4F7FB", "#C5D4E4", "#2A5678"),  # icy blue
    ("#F7F4EF", "#E4D5C2", "#6E5A3A"),  # platinum
    ("#F3FBFA", "#C9E7E0", "#1F7A64"),  # mint
    ("#F7F4FC", "#DDD3F1", "#4C3A86"),  # lavender
    ("#FBF4F2", "#F3D0C8", "#A33B32"),  # coral
    ("#FBF6EC", "#F3E0B8", "#8A5A10"),  # amber
]

# package -> candidate launcher activities. None of these were launched on a device.
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

SYSTEM_CANDIDATES = {
    "sys_phone": [
        "com.android.dialer/com.android.dialer.main.impl.MainActivity",
        "com.google.android.dialer/com.google.android.dialer.extensions.GoogleDialtactsActivity",
    ],
    "sys_messages": [
        "com.google.android.apps.messaging/com.google.android.apps.messaging.ui.ConversationListActivity",
        "com.android.messaging/com.android.messaging.ui.conversationlist.ConversationListActivity",
    ],
    "sys_camera": [
        "com.android.camera2/com.android.camera.CameraLauncher",
    ],
    "sys_photos": [
        "com.google.android.apps.photos/com.google.android.apps.photos.home.HomeActivity",
    ],
    "sys_settings": [
        "com.android.settings/com.android.settings.Settings",
    ],
    "sys_clock": [
        "com.google.android.deskclock/com.android.deskclock.DeskClock",
        "com.android.deskclock/com.android.deskclock.DeskClock",
    ],
    "sys_calendar": [
        "com.google.android.calendar/com.android.calendar.AllInOneActivity",
    ],
    "sys_browser": [
        "com.android.chrome/com.google.android.apps.chrome.Main",
    ],
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


def circle_d(cx: float, cy: float, r: float, sweep: int = 0) -> str:
    return (
        f"M{cx - r:.2f} {cy:.2f} "
        f"a{r:.2f} {r:.2f} 0 1 {sweep} {2 * r:.2f} 0 "
        f"a{r:.2f} {r:.2f} 0 1 {sweep} {-2 * r:.2f} 0"
    )


def star_d(cx: float, cy: float, outer: float, inner: float) -> str:
    pts = []
    for i in range(8):
        ang = -math.pi / 2 + i * math.pi / 4
        radius = outer if i % 2 == 0 else inner
        pts.append(f"{cx + radius * math.cos(ang):.2f} {cy + radius * math.sin(ang):.2f}")
    return "M " + " L ".join(pts) + " Z"


def ring(cx: float, cy: float, outer: float, inner: float) -> str:
    return circle_d(cx, cy, outer, 0) + " " + circle_d(cx, cy, inner, 1)


def parts_to_svg(parts: list[tuple]) -> str:
    chunks = []
    for part in parts:
        kind = part[0]
        if kind == "c":
            _, fill, cx, cy, r = part
            chunks.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"/>')
        elif kind == "r":
            _, fill, x, y, w, h, rx = part
            chunks.append(
                f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>'
            )
        elif kind == "e":
            _, fill, cx, cy, rx, ry = part
            chunks.append(
                f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}"/>'
            )
        elif kind == "p":
            _, fill, d = part
            chunks.append(f'<path d="{d}" fill="{fill}"/>')
        elif kind == "o":
            _, fill, d = part
            chunks.append(f'<path d="{d}" fill="{fill}" fill-rule="evenodd"/>')
        elif kind == "s":
            _, stroke, width, d = part
            chunks.append(
                f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{width}" '
                f'stroke-linecap="round" stroke-linejoin="round"/>'
            )
        elif kind == "raw":
            chunks.append(part[1])
        else:
            raise ValueError(kind)
    return "\n    ".join(chunks)


def plate_svg(slug: str, plate_index: int, parts: list[tuple]) -> str:
    top, bottom, _accent = PLATES[plate_index % len(PLATES)]
    gid = slug.replace("_", "")
    body = parts_to_svg(parts)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <defs>
    <linearGradient id="{gid}bg" x1="36" y1="18" x2="160" y2="176" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{top}"/>
      <stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
    <linearGradient id="{gid}glass" x1="96" y1="20" x2="96" y2="108" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.78"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="{gid}clip">
      <rect x="14" y="14" width="164" height="164" rx="50"/>
    </clipPath>
  </defs>
  <rect x="14" y="14" width="164" height="164" rx="50" fill="url(#{gid}bg)"/>
  <g clip-path="url(#{gid}clip)">
    <ellipse cx="74" cy="58" rx="62" ry="36" fill="#ffffff" fill-opacity="0.28"/>
    <path d="M30 86C48 48 78 30 108 30c10 0 18 2 26 6-30 2-62 24-84 58-8 12-14 24-16 34-4-14-6-28-4-42z" fill="url(#{gid}glass)"/>
  </g>
  <rect x="15" y="15" width="162" height="162" rx="49" fill="none" stroke="#F8FBFF" stroke-opacity="0.9" stroke-width="1.6"/>
  <rect x="17.2" y="17.2" width="157.6" height="157.6" rx="47.5" fill="none" stroke="#7E90A4" stroke-opacity="0.28" stroke-width="1"/>
  <g>
    {body}
  </g>
</svg>
'''


def glyph_geometry(parts: list[tuple]) -> str:
    return json.dumps(parts, sort_keys=False)


def app_glyphs(accent_of) -> dict[str, list[tuple]]:
    """One original silhouette per chart app. Accent is per-icon, ink is shared."""
    g: dict[str, list[tuple]] = {}

    def A(plate: int) -> str:
        return accent_of(plate)

    # 1 Muse — crescent of light, not a wordmark.
    g["muse"] = [
        ("o", INK, circle_d(90, 104, 34, 0) + " " + circle_d(108, 94, 24, 1)),
        ("c", A(0), 68, 76, 6.5),
    ]
    # 2 ChatGPT — conversation tile and a spark. Not the knot logo.
    g["chatgpt"] = [
        ("r", INK, 62, 78, 68, 46, 18),
        ("p", INK, "M78 124 L96 142 L112 124 Z"),
        ("p", A(1), star_d(96, 64, 14, 6)),
    ]
    # 3 TikTok Pro — event ticket, distinct from the video disc below.
    g["tiktok_pro"] = [
        ("p", INK, "M80 64 H124 V86 A10 10 0 0 0 124 106 V128 H80 V106 A10 10 0 0 0 80 86 Z"),
        ("p", PAPER, star_d(102, 96, 9, 3.8)),
    ]
    # 4 Capital One — vault door.
    g["capital_one"] = [
        ("o", INK, ring(96, 96, 36, 16)),
        ("c", A(3), 96, 90, 7),
        ("r", A(3), 92, 96, 8, 18, 2),
    ]
    # 5 Settings Home — house with a control notch.
    g["settings_home"] = [
        ("p", INK, "M96 58 L140 96 H126 V132 H66 V96 H52 Z"),
        ("r", PAPER, 88, 104, 16, 28, 2),
        ("r", A(4), 70, 86, 22, 6, 3),
    ]
    # 6 Vinted — hanger.
    g["vinted"] = [
        ("s", INK, 8, "M96 58 V74"),
        ("s", INK, 8, "M78 86 C78 70 114 70 114 86"),
        ("p", INK, "M64 90 H128 L96 128 Z"),
        ("c", A(5), 96, 104, 5),
    ]
    # 7 WhatsApp — bubble and fold, no handset.
    g["whatsapp"] = [
        ("r", INK, 58, 66, 76, 52, 22),
        ("p", INK, "M78 118 L92 138 L108 118 Z"),
        ("s", PAPER, 6, "M78 92 C90 104 108 104 120 88"),
    ]
    # 8 McDonald's — cup, not arches.
    g["mcdonalds"] = [
        ("p", INK, "M74 84 H118 L110 132 H82 Z"),
        ("e", A(1), 96, 82, 26, 8),
        ("r", A(1), 108, 58, 6, 28, 3),
    ]
    # 9 TikTok — disc and play wedge.
    g["tiktok"] = [
        ("o", INK, ring(90, 98, 34, 10)),
        ("p", A(2), "M112 84 L112 112 L136 98 Z"),
    ]
    # 10 FreeReels — film reel hubs.
    g["freereels"] = [
        ("o", INK, ring(96, 96, 36, 8)
         + " " + circle_d(96, 68, 6, 1)
         + " " + circle_d(124, 96, 6, 1)
         + " " + circle_d(96, 124, 6, 1)
         + " " + circle_d(68, 96, 6, 1)),
        ("c", A(3), 96, 96, 4),
    ]
    # 11 FreeDrama — spotlight cone.
    g["freedrama"] = [
        ("p", INK, "M96 56 L138 126 H54 Z"),
        ("e", A(4), 96, 130, 40, 9),
        ("c", A(4), 96, 62, 6),
    ]
    # 12 Instagram — two prints and a peak, not a camera glyph.
    g["instagram"] = [
        ("r", INK, 84, 60, 46, 54, 8),
        ("r", A(5), 62, 78, 52, 56, 8),
        ("p", PAPER, "M74 118 L88 100 L100 112 L112 96 L122 118 Z"),
        ("c", PAPER, 78, 92, 4),
    ]
    # 13 DealSeek — price tag.
    g["dealseek"] = [
        ("p", INK, "M58 78 H112 L136 102 L112 126 H58 Z"),
        ("c", PAPER, 78, 102, 7),
        ("r", A(0), 96, 98, 22, 8, 3),
    ]
    # 14 PineDrama — fanned cards.
    g["pinedrama"] = [
        ("r", INK, 86, 62, 44, 58, 8),
        ("r", A(1), 70, 74, 44, 58, 8),
        ("r", "#F7FBFF", 78, 92, 28, 6, 3),
        ("r", "#F7FBFF", 78, 104, 20, 6, 3),
    ]
    # 15 Cleanup — broom.
    g["cleanup"] = [
        ("r", INK, 90, 52, 10, 52, 4),
        ("p", A(2), "M66 102 H126 L114 136 H78 Z"),
        ("s", PAPER, 3, "M80 112 H112 M84 122 H108"),
    ]
    # 16 TikTok Lite — a single feather, not a second disc.
    g["tiktok_lite"] = [
        ("p", INK, "M96 48 C128 74 124 112 96 144 C68 112 64 74 96 48 Z"),
        ("s", PAPER, 4, "M96 64 V128"),
        ("c", A(3), 96, 78, 5),
    ]
    # 17 Temu — shopping bag.
    g["temu"] = [
        ("r", INK, 66, 84, 60, 52, 10),
        ("s", INK, 8, "M80 84 C80 62 112 62 112 84"),
        ("c", A(4), 96, 108, 6),
    ]
    # 18 Kalshi — three market bars.
    g["kalshi"] = [
        ("r", INK, 62, 96, 16, 40, 4),
        ("r", A(5), 88, 64, 16, 72, 4),
        ("r", INK, 114, 80, 16, 56, 4),
    ]
    # 19 Cash App — folded note, no currency sign.
    g["cashapp"] = [
        ("r", INK, 58, 74, 76, 52, 8),
        ("p", A(0), "M108 74 L134 74 L134 100 Z"),
        ("r", PAPER, 74, 100, 30, 7, 3),
    ]
    # 20 Facebook — person on a card.
    g["facebook"] = [
        ("r", INK, 60, 60, 72, 76, 18),
        ("c", PAPER, 96, 88, 12),
        ("p", PAPER, "M74 124 C74 108 118 108 118 124 Z"),
    ]
    # 21 X — broadcast arcs. The letter X is the product mark, so it is not used.
    g["x"] = [
        ("c", INK, 78, 96, 10),
        ("s", INK, 8, "M96 78 A26 26 0 0 1 96 114"),
        ("s", A(2), 8, "M108 66 A42 42 0 0 1 108 126"),
    ]
    # 22 Walmart — cart.
    g["walmart"] = [
        ("r", INK, 58, 70, 22, 8, 3),
        ("p", INK, "M84 78 H134 L124 114 H94 Z"),
        ("c", A(3), 102, 128, 8),
        ("c", A(3), 124, 128, 8),
        ("c", PAPER, 102, 128, 3),
        ("c", PAPER, 124, 128, 3),
    ]
    # 23 Snapchat — gem, not a ghost.
    g["snapchat"] = [
        ("p", INK, "M96 56 L136 96 L96 140 L56 96 Z"),
        ("p", A(4), "M96 78 L114 96 L96 114 L78 96 Z"),
    ]
    # 24 CapCut — scissors.
    g["capcut"] = [
        ("p", INK, "M90 96 L66 58 L80 50 L104 92 Z"),
        ("p", INK, "M102 96 L126 58 L112 50 L88 92 Z"),
        ("c", INK, 96, 100, 7),
        ("o", A(5), ring(72, 126, 15, 6)),
        ("o", A(5), ring(120, 126, 15, 6)),
    ]
    # 25 BlinkDrama — eyelid over a lens.
    g["blinkdrama"] = [
        ("p", INK, "M52 102 C74 72 118 72 140 102 C118 132 74 132 52 102 Z"),
        ("c", A(0), 96, 102, 12),
        ("c", PAPER, 101, 97, 4),
    ]
    # 26 Telegram — sealed letter, not a paper plane.
    g["telegram"] = [
        ("r", INK, 58, 72, 76, 54, 8),
        ("p", A(1), "M58 76 L96 108 L134 76 L122 76 L96 96 L70 76 Z"),
        ("c", PAPER, 96, 108, 5),
    ]
    # 27 Peacock — screen and play, not a bird.
    g["peacock"] = [
        ("r", INK, 48, 64, 96, 68, 16),
        ("r", PAPER, 62, 78, 68, 40, 8),
        ("p", A(2), "M86 88 L86 110 L110 99 Z"),
    ]
    # 28 DramaWave — a card cut by three swells.
    g["dramawave"] = [
        ("r", INK, 58, 60, 76, 72, 14),
        ("s", PAPER, 7, "M72 88 C84 78 96 98 108 88 S128 78 132 90"),
        ("s", A(3), 7, "M72 108 C84 98 96 118 108 108 S128 98 132 110"),
    ]
    # 29 MapQuest — map pin.
    g["mapquest"] = [
        (
            "o",
            INK,
            "M96 142 C96 142 58 104 58 78 A38 38 0 1 1 134 78 C134 104 96 142 96 142 Z "
            + circle_d(96, 76, 10, 1),
        ),
    ]
    # 30 Freecash — stacked coins.
    g["freecash"] = [
        ("e", INK, 96, 118, 32, 12),
        ("e", A(5), 96, 104, 32, 12),
        ("e", INK, 96, 90, 32, 12),
        ("e", PAPER, 96, 86, 16, 5),
    ]
    # 31 Claude — open book and a small sun. Not a starburst mark.
    g["claude"] = [
        ("p", INK, "M96 78 L64 70 L64 122 L96 130 Z"),
        ("p", A(0), "M96 78 L128 70 L128 122 L96 130 Z"),
        ("s", PAPER, 4, "M96 86 V122"),
        ("c", A(0), 96, 60, 6),
    ]
    # 32 Whatnot — gavel.
    g["whatnot"] = [
        ("p", INK, "M58 112 L96 74 L112 90 L74 128 Z"),
        ("r", A(1), 108, 96, 28, 10, 4),
        ("p", A(1), "M124 100 L146 122 L136 132 L114 110 Z"),
    ]
    # 33 DramaBox — open box.
    g["dramabox"] = [
        ("p", INK, "M60 96 L96 78 L132 96 L96 114 Z"),
        ("p", A(2), "M60 96 L60 122 L96 140 L96 114 Z"),
        ("p", INK, "M132 96 L132 122 L96 140 L96 114 Z"),
        ("p", PAPER, "M88 108 L88 122 L102 114 Z"),
    ]
    # 34 TextNow — handset.
    g["textnow"] = [
        ("s", INK, 14, "M68 120 C62 72 116 60 132 98"),
        ("c", INK, 66, 124, 13),
        ("c", INK, 134, 98, 13),
        ("c", A(3), 126, 60, 9),
    ]
    # 35 Life360 — two rings and a center.
    g["life360"] = [
        ("o", INK, ring(96, 96, 38, 30)),
        ("o", A(4), ring(96, 96, 22, 14)),
        ("c", INK, 96, 96, 5),
    ]
    # 36 Messenger — two bubbles, no bolt.
    g["messenger"] = [
        ("c", INK, 80, 108, 26),
        ("p", INK, "M64 120 L70 142 L92 124 Z"),
        ("c", A(5), 118, 82, 22),
        ("p", A(5), "M126 96 L146 112 L122 104 Z"),
    ]
    return g


def system_glyphs(accent_of) -> dict[str, tuple[str, int, list[tuple]]]:
    A = accent_of
    return {
        "sys_phone": ("Phone", 0, [
            ("p", INK, "M70 78 C70 64 86 58 98 68 L108 84 C100 92 100 108 112 116 L126 124 C138 132 132 150 114 144 C80 134 62 104 70 78 Z"),
        ]),
        "sys_messages": ("Messages", 1, [
            ("r", INK, 52, 64, 88, 58, 20),
            ("p", INK, "M78 122 L96 142 L114 122 Z"),
        ]),
        "sys_camera": ("Camera", 2, [
            ("r", INK, 48, 74, 96, 62, 16),
            ("r", INK, 74, 60, 28, 16, 6),
            ("o", PAPER, ring(96, 106, 18, 8)),
        ]),
        "sys_photos": ("Photos", 3, [
            ("r", INK, 78, 58, 56, 64, 8),
            ("r", A(3), 56, 74, 56, 64, 8),
            ("c", PAPER, 74, 92, 6),
            ("p", PAPER, "M68 122 L84 104 L98 116 L112 100 L122 122 Z"),
        ]),
        "sys_settings": ("Settings", 4, [
            ("o", INK, ring(96, 96, 18, 8)),
            ("r", INK, 88, 48, 16, 18, 3),
            ("r", INK, 88, 126, 16, 18, 3),
            ("r", INK, 48, 88, 18, 16, 3),
            ("r", INK, 126, 88, 18, 16, 3),
            ("r", A(4), 126, 58, 14, 14, 3),
        ]),
        "sys_clock": ("Clock", 5, [
            ("o", INK, ring(96, 96, 38, 30)),
            ("p", INK, "M94 70 H102 V100 L120 112 L114 122 L90 104 Z"),
        ]),
        "sys_calendar": ("Calendar", 0, [
            ("r", INK, 52, 66, 88, 74, 12),
            ("r", A(0), 52, 66, 88, 22, 8),
            ("r", PAPER, 72, 54, 8, 22, 3),
            ("r", PAPER, 112, 54, 8, 22, 3),
        ]),
        "sys_browser": ("Browser", 1, [
            ("o", INK, ring(96, 96, 38, 30)),
            ("e", A(1), 96, 96, 14, 30),
            ("r", A(1), 66, 92, 60, 8, 2),
        ]),
        "sys_calculator": ("Calculator", 2, [
            ("r", INK, 56, 48, 80, 96, 14),
            ("r", PAPER, 70, 62, 52, 16, 4),
            ("c", A(2), 76, 100, 6),
            ("c", A(2), 96, 100, 6),
            ("c", A(2), 116, 100, 6),
            ("c", PAPER, 76, 120, 6),
            ("c", PAPER, 96, 120, 6),
            ("c", PAPER, 116, 120, 6),
        ]),
        "sys_contacts": ("Contacts", 3, [
            ("c", INK, 96, 78, 18),
            ("p", INK, "M58 132 C62 104 130 104 134 132 Z"),
        ]),
        "sys_files": ("Files", 4, [
            ("p", INK, "M52 72 H88 L100 86 H140 V132 H52 Z"),
            ("r", A(4), 70, 100, 36, 8, 3),
        ]),
        "sys_weather": ("Weather", 5, [
            ("c", A(5), 78, 80, 16),
            ("p", INK, "M70 112 H132 C140 112 140 96 128 96 H126 C128 80 108 74 100 86 C96 78 80 80 78 90 C64 90 62 112 70 112 Z"),
        ]),
        "sys_notes": ("Notes", 0, [
            ("r", INK, 58, 52, 76, 92, 10),
            ("r", PAPER, 74, 74, 44, 6, 3),
            ("r", PAPER, 74, 90, 44, 6, 3),
            ("r", A(0), 74, 106, 28, 6, 3),
        ]),
        "sys_music": ("Music", 1, [
            ("c", INK, 74, 124, 16),
            ("c", A(1), 118, 112, 14),
            ("r", INK, 86, 56, 8, 68, 3),
            ("r", INK, 86, 56, 46, 8, 3),
            ("r", A(1), 128, 64, 8, 48, 3),
        ]),
        "sys_flashlight": ("Flashlight", 2, [
            ("r", INK, 80, 78, 32, 62, 10),
            ("r", A(2), 74, 62, 44, 20, 6),
            ("c", A(2), 96, 48, 6),
        ]),
        "sys_recorder": ("Recorder", 3, [
            ("r", INK, 84, 52, 24, 52, 12),
            ("s", INK, 8, "M70 86 H58 M134 86 H122"),
            ("p", A(3), "M64 108 H128 V120 A32 18 0 0 1 64 120 Z"),
        ]),
    }


def app_specs() -> list[dict]:
    """Ranks follow the primary Play snapshot. Plates alternate so neighbors differ."""
    rows = [
        (1, "com.facebook.aura", "Muse", "muse"),
        (2, "com.openai.chatgpt", "ChatGPT", "chatgpt"),
        (3, "com.ss.android.ugc.tiktok.pro", "TikTok Pro", "tiktok_pro"),
        (4, "com.konylabs.capitalone", "Capital One", "capital_one"),
        (5, "com.eet.settings.launcher", "Settings Home", "settings_home"),
        (6, "fr.vinted", "Vinted", "vinted"),
        (7, "com.whatsapp", "WhatsApp", "whatsapp"),
        (8, "com.mcdonalds.app", "McDonald's", "mcdonalds"),
        (9, "com.zhiliaoapp.musically", "TikTok", "tiktok"),
        (10, "com.freereels.app", "FreeReels", "freereels"),
        (11, "com.drama.free", "FreeDrama", "freedrama"),
        (12, "com.instagram.android", "Instagram", "instagram"),
        (13, "com.dealseekorg.dealseek", "DealSeek", "dealseek"),
        (14, "com.ss.android.ttmd.video", "PineDrama", "pinedrama"),
        (15, "com.storage.androidcleaner", "Cleanup", "cleanup"),
        (16, "com.tiktok.lite.go", "TikTok Lite", "tiktok_lite"),
        (17, "com.einnovation.temu", "Temu", "temu"),
        (18, "com.kalshi.mobile", "Kalshi", "kalshi"),
        (19, "com.squareup.cash", "Cash App", "cashapp"),
        (20, "com.facebook.katana", "Facebook", "facebook"),
        (21, "com.twitter.android", "X", "x"),
        (22, "com.walmart.android", "Walmart", "walmart"),
        (23, "com.snapchat.android", "Snapchat", "snapchat"),
        (24, "com.lemon.lvoverseas", "CapCut", "capcut"),
        (25, "com.blink.drama.player", "BlinkDrama", "blinkdrama"),
        (26, "org.telegram.messenger", "Telegram", "telegram"),
        (27, "com.peacocktv.peacockandroid", "Peacock", "peacock"),
        (28, "com.dramawave.app", "DramaWave", "dramawave"),
        (29, "com.mapquest.android.ace", "MapQuest", "mapquest"),
        (30, "com.freecash.app2", "Freecash", "freecash"),
        (31, "com.anthropic.claude", "Claude", "claude"),
        (32, "com.whatnot_mobile", "Whatnot", "whatnot"),
        (33, "com.storymatrix.drama", "DramaBox", "dramabox"),
        (34, "com.enflick.android.TextNow", "TextNow", "textnow"),
        (35, "com.life360.android.safetymapd", "Life360", "life360"),
        (36, "com.facebook.orca", "Messenger", "messenger"),
    ]
    glyphs = app_glyphs(lambda plate: PLATES[plate % 6][2])
    specs = []
    for rank, package_id, short, slug in rows:
        specs.append(
            {
                "kind": "app",
                "rank": rank,
                "packageId": package_id,
                "short": short,
                "slug": slug,
                "drawable": f"ic_{slug}",
                "plate": (rank - 1) % 6,
                "parts": glyphs[slug],
                "activities": CANDIDATES.get(package_id, []),
            }
        )
    return specs


def system_specs() -> list[dict]:
    glyphs = system_glyphs(lambda plate: PLATES[plate % 6][2])
    specs = []
    for index, (slug, (title, plate, parts)) in enumerate(glyphs.items()):
        specs.append(
            {
                "kind": "system",
                "rank": "",
                "packageId": "",
                "short": title,
                "slug": slug,
                "drawable": slug,
                "plate": plate,
                "parts": parts,
                "activities": [],
                "components": SYSTEM_CANDIDATES.get(slug, []),
            }
        )
    return specs


def fallback_parts() -> list[tuple]:
    return [
        ("o", INK, circle_d(96, 104, 30, 0) + " " + circle_d(112, 96, 20, 1)),
        ("r", PLATES[5][2], 90, 70, 12, 46, 6),
    ]


def write_svg(path: Path, slug: str, plate: int, parts: list[tuple]) -> None:
    path.write_text(plate_svg(slug, plate, parts), encoding="utf-8")


def rasterize(svg: Path, png: Path, size: int) -> None:
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
        check=True,
    )


def check_png(png: Path, slug: str) -> dict:
    im = Image.open(png).convert("RGBA")
    if im.size != (192, 192):
        raise SystemExit(f"{slug} png is {im.size}")
    px = im.load()
    if px[0, 0][3] != 0 or px[191, 0][3] != 0:
        raise SystemExit(f"{slug} corners are not transparent")
    if px[96, 96][3] < 250:
        raise SystemExit(f"{slug} center is not opaque")
    small = im.resize((48, 48), Image.Resampling.LANCZOS)
    sp = small.load()
    dark = []
    for y in range(48):
        for x in range(48):
            r, g, b, a = sp[x, y]
            if a > 220 and (r + g + b) / 3 < 125:
                dark.append((x, y))
    if len(dark) < 40:
        raise SystemExit(f"{slug} glyph is too faint at 48px ({len(dark)} dark pixels)")
    xs = [p[0] for p in dark]
    ys = [p[1] for p in dark]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    if span < 14:
        raise SystemExit(f"{slug} glyph is too small at 48px (span {span})")
    if abs(cx - 23.5) > 7 or abs(cy - 23.5) > 7:
        raise SystemExit(f"{slug} glyph is off center at 48px ({cx:.1f},{cy:.1f})")
    return {"dark48": len(dark), "span48": span, "center48": [round(cx, 1), round(cy, 1)]}


def xml_comment_header() -> str:
    return (
        "<!-- PROTOTYPE. Candidate launcher components are widely published names. "
        "mapping_verified is false. launcher_tested is false. "
        "No activity in this file was confirmed on a device. -->\n"
    )


def write_mappings(app_rows: list[dict], system_rows: list[dict]) -> None:
    XML_DIR.mkdir(parents=True, exist_ok=True)
    items = []
    for row in app_rows:
        for activity in row["activities"]:
            items.append(
                f'    <item component="ComponentInfo{{{row["packageId"]}/{activity}}}" drawable="{row["drawable"]}"/>'
            )
    for row in system_rows:
        for component in row.get("components", []):
            items.append(
                f'    <item component="ComponentInfo{{{component}}}" drawable="{row["drawable"]}"/>'
            )
    appfilter = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        + xml_comment_header()
        + "<resources>\n"
        + '    <iconback img1="iconback"/>\n'
        + '    <iconmask img1="iconmask"/>\n'
        + '    <iconupon img1="iconupon"/>\n'
        + '    <scale factor="1.0"/>\n'
        + "\n".join(items)
        + "\n</resources>\n"
    )
    (XML_DIR / "appfilter.xml").write_text(appfilter, encoding="utf-8")

    drawables = ['    <category title="Luma"/>']
    for row in app_rows + system_rows:
        drawables.append(f'    <item drawable="{row["drawable"]}"/>')
    drawable_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        + xml_comment_header()
        + "<resources>\n"
        + "\n".join(drawables)
        + "\n</resources>\n"
    )
    (XML_DIR / "drawable.xml").write_text(drawable_xml, encoding="utf-8")

    appmap_items = []
    for row in app_rows:
        for activity in row["activities"]:
            appmap_items.append(f'    <item class="{activity}" name="{row["drawable"]}"/>')
    appmap = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        + xml_comment_header()
        + "<appmap>\n"
        + "\n".join(appmap_items)
        + "\n</appmap>\n"
    )
    (XML_DIR / "appmap.xml").write_text(appmap, encoding="utf-8")
    for name in ("appfilter.xml", "drawable.xml", "appmap.xml"):
        ET.parse(XML_DIR / name)

    values_xml = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="theme_title">Luma</string>
    <string name="theme_author">metaPhasic Group</string>
    <string-array name="icon_pack" translatable="false">
        <item>com.metaphasic.luma</item>
    </string-array>
</resources>
"""
    VALUES.mkdir(parents=True, exist_ok=True)
    (VALUES / "icon_pack.xml").write_text(values_xml, encoding="utf-8")
    ET.parse(VALUES / "icon_pack.xml")


def write_dashboard(app_rows: list[dict], system_rows: list[dict], icon_dir: str) -> str:
    def card(row: dict, prefix: str) -> str:
        rank = f"Rank {row['rank']}" if row["kind"] == "app" else "System"
        pkg = row["packageId"] or "Core system icon, outside the chart count"
        return f'''<figure class="icon">
  <img src="{prefix}{row["drawable"]}.png" alt="{escape(row["short"])} icon" width="96" height="96"/>
  <figcaption>
    <strong>{escape(row["short"])}</strong>
    <span>{escape(rank)}</span>
    <span class="pkg">{escape(pkg)}</span>
  </figcaption>
</figure>'''

    app_cards = "\n".join(card(row, icon_dir) for row in app_rows)
    sys_cards = "\n".join(card(row, icon_dir) for row in system_rows)
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Luma — Icon Pack prototype</title>
  <style>
    :root {{
      --ink: #243044;
      --muted: #5c6b7c;
      --line: #d5e0ea;
      --bg: #e7eef4;
      --card: #f8fbfc;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "Segoe UI", Helvetica, Arial, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(900px 420px at 10% -10%, #ffffff 0%, rgba(255,255,255,0) 60%),
        linear-gradient(180deg, #f4f7fb 0%, var(--bg) 100%);
    }}
    header {{
      display: flex;
      gap: 28px;
      align-items: center;
      padding: 36px 48px 12px;
    }}
    .logo-slot {{
      width: 148px;
      height: 84px;
      border: 1.5px dashed #8aa0b5;
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      color: #607488;
      background: rgba(255,255,255,0.65);
      font-size: 12px;
      line-height: 1.35;
      padding: 8px;
    }}
    h1 {{
      font-weight: 560;
      font-size: 42px;
      letter-spacing: -0.04em;
      margin: 0 0 4px;
    }}
    .sub {{ color: var(--muted); margin: 0; font-size: 16px; }}
    .status {{
      display: inline-block;
      margin-top: 12px;
      background: #243044;
      color: white;
      border-radius: 999px;
      padding: 6px 12px;
      font-size: 12px;
      letter-spacing: 0.08em;
    }}
    .metrics {{
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      padding: 20px 48px 8px;
    }}
    .metric {{
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px 16px;
    }}
    .metric b {{ display: block; font-size: 28px; letter-spacing: -0.04em; }}
    .metric span {{ color: var(--muted); font-size: 13px; }}
    section {{ padding: 8px 48px 28px; }}
    h2 {{ font-size: 18px; font-weight: 600; margin: 18px 0 12px; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(168px, 1fr));
      gap: 14px;
    }}
    figure.icon {{
      margin: 0;
      background: rgba(255,255,255,0.72);
      border: 1px solid var(--line);
      border-radius: 22px;
      padding: 16px 12px 12px;
      text-align: center;
    }}
    figure img {{ width: 96px; height: 96px; }}
    figcaption {{ display: flex; flex-direction: column; gap: 2px; }}
    figcaption strong {{ font-size: 14px; }}
    figcaption span {{ color: var(--muted); font-size: 12px; }}
    .pkg {{
      font-family: ui-monospace, monospace;
      font-size: 10px !important;
      word-break: break-all;
    }}
    footer {{
      padding: 8px 48px 40px;
      color: var(--muted);
      font-size: 13px;
    }}
  </style>
</head>
<body>
  <header>
    <div class="logo-slot">metaPhasic Group logo<br/>was not attached<br/>to this workspace</div>
    <div>
      <h1>Luma</h1>
      <p class="sub">Icon pack prototype for metaPhasic Group. Interpretive symbols, not official app logos.</p>
      <div class="status">PROTOTYPE · NOT A PLAY RELEASE</div>
    </div>
  </header>
  <div class="metrics">
    <div class="metric"><b>199</b><span>chart apps with package IDs</span></div>
    <div class="metric"><b>{len(app_rows)}</b><span>original app icons drawn</span></div>
    <div class="metric"><b>0</b><span>mappings verified on a device</span></div>
    <div class="metric"><b>0</b><span>launcher tests completed</span></div>
  </div>
  <section>
    <h2>Chart icons</h2>
    <div class="grid">
      {app_cards}
    </div>
    <h2>System icons</h2>
    <div class="grid">
      {sys_cards}
    </div>
  </section>
  <footer>
    Artwork, mapping verification, and launcher testing are tracked separately.
    System icons are not part of the 300-app coverage count.
    Ranks 37–199 are catalogued and not yet drawn. Ranks 200–300 were not in the Play response.
  </footer>
</body>
</html>
'''


def contact_sheet(rows: list[dict], path: Path, size: int) -> None:
    columns = 8
    label_h = 36 if size >= 96 else 22
    cell = size + 16
    rows_n = math.ceil(len(rows) / columns)
    width = columns * cell + 32
    height = rows_n * (cell + label_h) + 32
    sheet = Image.new("RGBA", (width, height), (244, 247, 251, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, row in enumerate(rows):
        col = index % columns
        line = index // columns
        x = 16 + col * cell
        y = 16 + line * (cell + label_h)
        src = PNG_DIR / f"{row['drawable']}.png" if size == 192 else PNG48_DIR / f"{row['drawable']}.png"
        icon = Image.open(src).convert("RGBA")
        if icon.size != (size, size):
            icon = icon.resize((size, size), Image.Resampling.LANCZOS)
        sheet.alpha_composite(icon, (x + 8, y))
        draw.text((x + 8, y + size + 2), row["short"][:16], fill=(36, 48, 68, 255), font=font)
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, "PNG")


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "LiberationSans-Bold.ttf" if bold else "LiberationSans-Regular.ttf"
    path = Path("/usr/share/fonts/truetype/liberation") / name
    return ImageFont.truetype(str(path), size)


def feature_graphic(rows: list[dict]) -> None:
    canvas = Image.new("RGBA", (1024, 500), (231, 238, 244, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((28, 28, 996, 472), radius=36, fill=(248, 251, 252, 255))
    picks = [rows[i] for i in (0, 1, 6, 11, 17, 26)]
    for index, row in enumerate(picks):
        icon = Image.open(PNG_DIR / f"{row['drawable']}.png").convert("RGBA")
        icon = icon.resize((150, 150), Image.Resampling.LANCZOS)
        x = 56 + (index % 3) * 162
        y = 64 + (index // 3) * 176
        canvas.alpha_composite(icon, (x, y))
    draw.text((560, 132), "Luma", fill=(36, 48, 68, 255), font=load_font(78, bold=True))
    draw.text((560, 220), "Icon Pack", fill=(36, 48, 68, 255), font=load_font(36))
    draw.text((560, 278), "Prototype  ·  36 app icons drawn", fill=(92, 107, 124, 255), font=load_font(22))
    draw.text((560, 316), "16 system icons  ·  chart snapshot of 199", fill=(92, 107, 124, 255), font=load_font(22))
    draw.text((560, 370), "Not a finished Play listing", fill=(163, 59, 50, 255), font=load_font(22, bold=True))
    out = STORE / "feature-graphic-1024x500.png"
    canvas.convert("RGB").save(out, "PNG")


def main() -> None:
    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    by_rank = {app["rank"]: app for app in snapshot["primary"]["apps"]}
    apps = app_specs()
    systems = system_specs()
    geometries = {}
    for row in apps:
        chart = by_rank[row["rank"]]
        if chart["packageId"] != row["packageId"]:
            raise SystemExit(
                f"rank {row['rank']} expected {row['packageId']} catalog has {chart['packageId']}"
            )
        row["chartName"] = chart["name"]
        key = glyph_geometry(row["parts"])
        if key in geometries:
            raise SystemExit(f"duplicate glyph {row['slug']} and {geometries[key]}")
        geometries[key] = row["slug"]
    for row in systems:
        key = glyph_geometry(row["parts"])
        if key in geometries:
            raise SystemExit(f"system glyph duplicates {geometries[key]}: {row['slug']}")
        geometries[key] = row["slug"]

    for folder in (SVG_DIR, PNG_DIR, PNG48_DIR, DRAWABLE, ASSETS, DASH, PREVIEW, STORE, TRACKER):
        folder.mkdir(parents=True, exist_ok=True)

    # Remove stale exports so dropped icons cannot linger and be counted.
    for folder in (SVG_DIR, PNG_DIR, PNG48_DIR, DRAWABLE):
        for old in folder.glob("*"):
            if old.is_file():
                old.unlink()

    drawn = []
    stats = {}
    for row in apps + systems:
        svg = SVG_DIR / f"{row['drawable']}.svg"
        write_svg(svg, row["drawable"], row["plate"], row["parts"])
        png = PNG_DIR / f"{row['drawable']}.png"
        png48 = PNG48_DIR / f"{row['drawable']}.png"
        rasterize(svg, png, 192)
        rasterize(svg, png48, 48)
        stats[row["drawable"]] = check_png(png, row["drawable"])
        shutil.copyfile(png, DRAWABLE / png.name)
        drawn.append(row)

    # Launcher resources that are not app coverage.
    write_svg(SVG_DIR / "ic_launcher.svg", "iclauncher", 0, fallback_parts())
    rasterize(SVG_DIR / "ic_launcher.svg", PNG_DIR / "ic_launcher.png", 192)
    rasterize(SVG_DIR / "ic_launcher.svg", STORE / "play-icon-512.png", 512)
    shutil.copyfile(PNG_DIR / "ic_launcher.png", DRAWABLE / "ic_launcher.png")
    check_png(PNG_DIR / "ic_launcher.png", "ic_launcher")

    mask = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <rect x="14" y="14" width="164" height="164" rx="50" fill="#ffffff"/>
</svg>
'''
    upon = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <path d="M36 78C56 40 88 28 120 32c-28 6-58 28-74 62-6 12-8 22-8 30 0-16 2-32 6-46z" fill="#ffffff" fill-opacity="0.55"/>
</svg>
'''
    (SVG_DIR / "iconmask.svg").write_text(mask, encoding="utf-8")
    (SVG_DIR / "iconupon.svg").write_text(upon, encoding="utf-8")
    write_svg(SVG_DIR / "iconback.svg", "iconback", 0, [])
    for name, size in (("iconback", 192), ("iconmask", 192), ("iconupon", 192)):
        rasterize(SVG_DIR / f"{name}.svg", PNG_DIR / f"{name}.png", size)
        shutil.copyfile(PNG_DIR / f"{name}.png", DRAWABLE / f"{name}.png")

    write_mappings(apps, systems)

    html_assets = write_dashboard(apps, systems, "icons/")
    html_preview = write_dashboard(apps, systems, "../artwork/png/192/")
    asset_icons = ASSETS / "icons"
    if asset_icons.exists():
        shutil.rmtree(asset_icons)
    asset_icons.mkdir(parents=True)
    for row in drawn:
        shutil.copyfile(PNG_DIR / f"{row['drawable']}.png", asset_icons / f"{row['drawable']}.png")
    (ASSETS / "index.html").write_text(html_assets, encoding="utf-8")
    (DASH / "index.html").write_text(html_preview, encoding="utf-8")

    contact_sheet(apps + systems, PREVIEW / "contact-sheet-192.png", 192)
    contact_sheet(apps + systems, PREVIEW / "small-48.png", 48)
    feature_graphic(apps)

    tracker_rows = []
    for row in apps + systems:
        activities = row["activities"] or [
            component.split("/", 1)[1] for component in row.get("components", [])
        ]
        tracker_rows.append(
            {
                "kind": row["kind"],
                "rank": row["rank"],
                "chart_name": row.get("chartName", row["short"]),
                "short_name": row["short"],
                "package_id": row["packageId"],
                "drawable": row["drawable"],
                "artwork": "prototype",
                "svg": f"artwork/svg/{row['drawable']}.svg",
                "png_192": f"artwork/png/192/{row['drawable']}.png",
                "mapping_verified": "false",
                "candidate_activities": " ".join(activities),
                "launcher_tested": "false",
                "counts_as_app_coverage": "true" if row["kind"] == "app" else "false",
                "dark_pixels_at_48": stats[row["drawable"]]["dark48"],
            }
        )
    fieldnames = list(tracker_rows[0].keys())
    with (TRACKER / "progress.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(tracker_rows)
    summary = {
        "status": "prototype",
        "release_ready": False,
        "signed_package": False,
        "compiled": False,
        "chart_apps_with_package_ids": snapshot["coverageRecorded"],
        "coverage_target": 300,
        "app_icons_drawn": len(apps),
        "system_icons_drawn": len(systems),
        "generic_fallbacks_counted_as_apps": 0,
        "mapping_verified": 0,
        "launcher_tested": 0,
        "duplicate_glyph_geometries": 0,
        "duplicate_package_ids": 0,
    }
    (TRACKER / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
