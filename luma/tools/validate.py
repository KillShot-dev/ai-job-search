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


if __name__ == "__main__":
    main()
