#!/usr/bin/env python3
"""Record the U.S. Top Free chart snapshot used by Luma.

Reads the HTML/JSON captured for this prototype and writes
research/us-top-free-snapshot.json. It does not fill missing ranks.
"""

from __future__ import annotations

import json
import re
from html import unescape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "research" / "us-top-free-snapshot.json"

PLAY_JSON = Path("/tmp/play-top-free-us.json")
AB_PAGES = [Path("/tmp/ab.html"), Path("/tmp/ab2.html")]
APPINSIDER = Path("/tmp/chart.html")


def parse_appbrain(paths: list[Path]) -> list[dict]:
    rows = []
    for path in paths:
        html = path.read_text(encoding="utf-8", errors="replace")
        for rank, body in re.findall(
            r'<td class="ranking-rank">(\d+)</td>(.*?)</tr>', html, re.S
        ):
            pkg = re.search(r'href="/app/[^"]+/([^"]+)"', body)
            name = re.search(
                r'class="ranking-app-cell">\s*<a[^>]*>([^<]+)</a>', body
            )
            dev = re.search(
                r'ranking-app-cell-creator">\s*by <a[^>]*>([^<]+)</a>', body
            )
            if not pkg or not name:
                continue
            rows.append(
                {
                    "rank": int(rank),
                    "name": unescape(name.group(1)).strip(),
                    "packageId": pkg.group(1),
                    "developer": unescape(dev.group(1)).strip() if dev else "",
                }
            )
    rows.sort(key=lambda row: row["rank"])
    return rows


def parse_appinsider(path: Path) -> dict:
    html = path.read_text(encoding="utf-8", errors="replace")
    stamp = re.search(r'datetime="([^"]+)"', html)
    names = [
        unescape(name).strip()
        for _, name in re.findall(r'class="app-link" href="([^"]+)"[^>]*>([^<]+)', html)
    ]
    packages = re.findall(
        r'https://appinsider\.io/android/app/([A-Za-z0-9_.]+)', html
    )
    # JSON-LD ItemList lists packages in rank order for the first 100 only.
    ld_packages = []
    seen = set()
    for pkg in packages:
        if pkg not in seen:
            seen.add(pkg)
            ld_packages.append(pkg)
    return {
        "updatedAt": stamp.group(1) if stamp else None,
        "names": names,
        "packageIdsFirst100": ld_packages[:100],
    }


def main() -> None:
    play = json.loads(PLAY_JSON.read_text(encoding="utf-8"))
    apps = []
    for index, app in enumerate(play["apps"], start=1):
        apps.append(
            {
                "rank": index,
                "name": app["title"],
                "packageId": app["appId"],
                "developer": app.get("developer") or "",
                "score": app.get("score"),
            }
        )
    package_ids = [app["packageId"] for app in apps]
    if len(package_ids) != len(set(package_ids)):
        raise SystemExit("primary snapshot contains duplicate package ids")

    appbrain = parse_appbrain(AB_PAGES)
    ab_by_pkg = {row["packageId"]: row for row in appbrain}
    present = {row["rank"] for row in appbrain}
    missing = [rank for rank in range(1, 201) if rank not in present]

    insider = parse_appinsider(APPINSIDER)
    play_names = {app["name"].casefold(): app for app in apps}
    insider_matched = 0
    for name in insider["names"]:
        if name.casefold() in play_names:
            insider_matched += 1

    same_rank = 0
    same_package_other_rank = 0
    for app in apps:
        other = ab_by_pkg.get(app["packageId"])
        if not other:
            continue
        if other["rank"] == app["rank"]:
            same_rank += 1
        else:
            same_package_other_rank += 1

    snapshot = {
        "coverageTarget": 300,
        "coverageRecorded": len(apps),
        "ranksNotInThisSnapshot": list(range(len(apps) + 1, 301)),
        "primary": {
            "label": "U.S. Google Play Top Free, all categories",
            "method": "google-play-scraper 10.1.4 list()",
            "collection": "TOP_FREE",
            "cluster": "topselling_free",
            "country": "us",
            "lang": "en",
            "requestedCount": 300,
            "returnedCount": len(apps),
            "fetchedAt": play["fetchedAt"],
            "sourceNote": play.get("source"),
            "limitation": (
                "The Play topselling_free response used here returned 199 apps "
                "when 300 were requested. Ranks 200 through 300 are omitted, not estimated."
            ),
            "apps": apps,
        },
        "crosschecks": {
            "appbrain": {
                "url": "https://www.appbrain.com/stats/google-play-rankings/top_free/all/us",
                "page2Url": "https://www.appbrain.com/stats/google-play-rankings/top_free/all/us/2",
                "pageLabel": "Last updated: October 25, 2026",
                "parsedRows": len(appbrain),
                "missingRanks": missing,
                "page3": (
                    "https://www.appbrain.com/stats/google-play-rankings/top_free/all/us/3 "
                    "returned the first page again (paywall), so it was not used."
                ),
                "apps": appbrain,
            },
            "appinsider": {
                "url": "https://appinsider.io/android/charts/us/all/free",
                "updatedAt": insider["updatedAt"],
                "nameCount": len(insider["names"]),
                "packageIdsPublishedInJsonLd": len(insider["packageIdsFirst100"]),
                "names": [
                    {"rank": index, "name": name}
                    for index, name in enumerate(insider["names"], start=1)
                ],
                "packageIdsFirst100": [
                    {"rank": index, "packageId": pkg}
                    for index, pkg in enumerate(insider["packageIdsFirst100"], start=1)
                ],
            },
        },
        "agreement": {
            "playPackagesAlsoOnAppbrain": same_rank + same_package_other_rank,
            "sameRankAndPackage": same_rank,
            "samePackageDifferentRank": same_package_other_rank,
            "playPackagesMissingOnParsedAppbrain": len(apps)
            - (same_rank + same_package_other_rank),
            "appinsiderNamesAlsoInPlayList": insider_matched,
            "appinsiderNameCount": len(insider["names"]),
        },
    }
    OUT.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {OUT} primary={len(apps)} appbrain={len(appbrain)} "
        f"missing={missing} sameRank={same_rank} otherRank={same_package_other_rank} "
        f"insiderNames={len(insider['names'])} insiderMatched={insider_matched}"
    )


if __name__ == "__main__":
    main()
