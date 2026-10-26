#!/usr/bin/env python3
"""Check the prototype inventory without regenerating artwork."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    summary = json.loads((ROOT / "tracker" / "summary.json").read_text(encoding="utf-8"))
    rows = list(csv.DictReader((ROOT / "tracker" / "progress.csv").open(encoding="utf-8")))
    apps = [row for row in rows if row["counts_as_app_coverage"] == "true"]
    systems = [row for row in rows if row["kind"] == "system"]
    if len(apps) != summary["app_icons_drawn"]:
        raise SystemExit("tracker app count does not match summary")
    if len(systems) != summary["system_icons_drawn"]:
        raise SystemExit("tracker system count does not match summary")
    if any(row["mapping_verified"] != "false" for row in rows):
        raise SystemExit("a mapping is marked verified")
    if any(row["launcher_tested"] != "false" for row in rows):
        raise SystemExit("a launcher test is marked done")
    packages = [row["package_id"] for row in apps]
    if len(packages) != len(set(packages)):
        raise SystemExit("duplicate package ids in app coverage")
    geometries = set()
    for row in rows:
        svg = (ROOT / row["svg"]).read_text(encoding="utf-8")
        png = Image.open(ROOT / row["png_192"]).convert("RGBA")
        if png.size != (192, 192):
            raise SystemExit(f"{row['drawable']} is not 192")
        if png.getpixel((0, 0))[3] != 0:
            raise SystemExit(f"{row['drawable']} corner is opaque")
        # Geometry identity is the drawable body after the plate defs.
        body = svg.split("<g>", 1)[1]
        if body in geometries:
            raise SystemExit(f"duplicate svg body {row['drawable']}")
        geometries.add(body)
    snapshot = json.loads(
        (ROOT / "research" / "us-top-free-snapshot.json").read_text(encoding="utf-8")
    )
    by_rank = {app["rank"]: app["packageId"] for app in snapshot["primary"]["apps"]}
    for row in apps:
        rank = int(row["rank"])
        if by_rank.get(rank) != row["package_id"]:
            raise SystemExit(f"rank {rank} is not the snapshot package")
    for name in ("appfilter.xml", "drawable.xml", "appmap.xml"):
        ET.parse(ROOT / "android" / "app" / "src" / "main" / "res" / "xml" / name)
    if summary["release_ready"] or summary["compiled"] or summary["signed_package"]:
        raise SystemExit("summary claims a release that was not produced")
    if summary["chart_apps_with_package_ids"] >= summary["coverage_target"]:
        raise SystemExit("snapshot unexpectedly reached the coverage target")
    print(
        f"validate ok apps={len(apps)} systems={len(systems)} "
        f"chart={summary['chart_apps_with_package_ids']} release_ready=false"
    )
    validate_logo_set()


def validate_logo_set() -> None:
    summary = json.loads((ROOT / "tracker" / "logo-summary.json").read_text(encoding="utf-8"))
    rows = list(csv.DictReader((ROOT / "tracker" / "logo-progress.csv").open(encoding="utf-8")))
    chart = json.loads((ROOT / "research" / "us-top-free-300.json").read_text(encoding="utf-8"))
    if summary["icons"] != 300 or summary["release_ready"] or summary["mapping_verified"] or summary["launcher_tested"]:
        raise SystemExit("logo summary is not an unverified 300-icon prototype")
    if summary["overall_ranks"] != 199 or summary["category_continuation"] != 101:
        raise SystemExit("logo summary chart split changed")
    if len(rows) != 300:
        raise SystemExit("logo tracker is not 300 rows")
    packages = [row["package_id"] for row in rows]
    if len(packages) != len(set(packages)):
        raise SystemExit("duplicate package in the logo set")
    if any(row["mapping_verified"] != "false" or row["launcher_tested"] != "false" for row in rows):
        raise SystemExit("logo tracker claims a verified mapping or launcher test")
    if any(row["counts_as_app_coverage"] != "true" for row in rows):
        raise SystemExit("a logo row is not counted as app coverage")
    by_rank = {app["rank"]: app for app in chart["apps"]}
    geometries = set()
    families = set()
    for row in rows:
        rank = int(row["rank"])
        app = by_rank.get(rank)
        if app is None or app["packageId"] != row["package_id"] or app["list"] != row["list"]:
            raise SystemExit(f"logo rank {rank} does not match the 300 chart")
        svg_path = ROOT / "artwork" / "logo" / "svg" / f"{row['drawable']}.svg"
        png_path = ROOT / "artwork" / "logo" / "png" / "192" / f"{row['drawable']}.png"
        small_path = ROOT / "artwork" / "logo" / "png" / "48" / f"{row['drawable']}.png"
        drawable = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi" / f"{row['drawable']}.png"
        for path in (svg_path, png_path, small_path, drawable):
            if not path.is_file():
                raise SystemExit(f"missing {path}")
        png = Image.open(png_path).convert("RGBA")
        if png.size != (192, 192) or png.getpixel((0, 0))[3] != 0 or png.getpixel((96, 96))[3] < 250:
            raise SystemExit(f"{row['drawable']} failed the tile check")
        body = svg_path.read_text(encoding="utf-8").split("</g>", 1)[1]
        if body in geometries:
            raise SystemExit(f"duplicate logo geometry {row['drawable']}")
        geometries.add(body)
        families.add(row["family"])
    if "mark" in families:
        raise SystemExit("logo set still contains an abstract mark fallback")
    brand = ROOT / "brand" / "metaphasic-group.png"
    if not brand.is_file():
        raise SystemExit("metaPhasic Group logo file is missing")
    dashboard = (ROOT / "dashboard" / "index.html").read_text(encoding="utf-8")
    if "metaPhasic Group" not in dashboard or "metaphasic-group.png" not in dashboard or dashboard.count("artwork/logo/png/192/") != 300:
        raise SystemExit("dashboard is not the branded 300-icon logo set")
    asset = (ROOT / "android" / "app" / "src" / "main" / "assets" / "dashboard" / "index.html").read_text(encoding="utf-8")
    if "metaPhasic Group" not in asset or asset.count('src="logo/') != 300:
        raise SystemExit("bundled dashboard is not the branded 300-icon logo set")
    appfilter = (ROOT / "android" / "app" / "src" / "main" / "res" / "xml" / "appfilter.xml").read_text(encoding="utf-8")
    if 'drawable="g007"' not in appfilter or "unverified" not in appfilter.lower() and "PROTOTYPE" not in appfilter:
        raise SystemExit("appfilter is not pointing at the logo set")
    print("validate logo ok icons=300 families=%d release_ready=false" % len(families))


if __name__ == "__main__":
    main()
