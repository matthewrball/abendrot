#!/usr/bin/env python3
"""Print GitHub release asset download counts for Abendrot."""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_REPO = "matthewrball/abendrot"
CAVEAT = "App downloads count .dmg and .zip release artifacts, not unique people or installs."
API_ROOT = "https://api.github.com"
APP_EXTENSIONS = (".dmg", ".zip")


def parse_repo(value: str) -> tuple[str, str]:
    parts = value.split("/")
    if len(parts) != 2 or not all(parts):
        raise argparse.ArgumentTypeError("repo must be OWNER/REPO")
    return parts[0], parts[1]


def next_link(header: str | None) -> str | None:
    if not header:
        return None
    for part in header.split(","):
        url_part, _, rel_part = part.strip().partition(";")
        if 'rel="next"' in rel_part:
            return url_part.strip()[1:-1]
    return None


def get_json(url: str, token: str | None) -> tuple[object, str | None]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "abendrot-download-counts",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response), response.headers.get("Link")
    except urllib.error.HTTPError as error:
        detail = error.reason
        try:
            body = json.loads(error.read().decode("utf-8"))
            detail = body.get("message", detail)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            pass
        raise RuntimeError(f"GitHub API error {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"GitHub API error: {error.reason}") from error


def fetch_releases(owner: str, repo: str, token: str | None) -> list[dict]:
    releases: list[dict] = []
    path = f"/repos/{owner}/{repo}/releases"
    url = API_ROOT + path + "?" + urllib.parse.urlencode({"per_page": 100})
    while url:
        payload, link_header = get_json(url, token)
        if not isinstance(payload, list):
            raise RuntimeError("GitHub API returned an unexpected response.")
        releases.extend(payload)
        url = next_link(link_header)
    return releases


def aggregate(releases: list[dict], repo: str = DEFAULT_REPO) -> dict:
    result = {
        "repo": repo,
        "caveat": CAVEAT,
        "releases": [],
        "total_app_downloads": 0,
        "total_other_asset_downloads": 0,
    }
    for release in releases:
        if release.get("draft"):
            continue
        assets = []
        app_downloads = 0
        other_downloads = 0
        for asset in release.get("assets") or []:
            count = int(asset.get("download_count") or 0)
            name = asset.get("name") or ""
            is_app = name.lower().endswith(APP_EXTENSIONS)
            assets.append({"name": name, "asset_downloads": count, "app_artifact": is_app})
            if is_app:
                app_downloads += count
            else:
                other_downloads += count
        result["releases"].append(
            {
                "tag": release.get("tag_name") or "",
                "name": release.get("name") or "",
                "prerelease": bool(release.get("prerelease")),
                "assets": assets,
                "app_downloads": app_downloads,
                "other_asset_downloads": other_downloads,
            }
        )
        result["total_app_downloads"] += app_downloads
        result["total_other_asset_downloads"] += other_downloads
    return result


def print_text(report: dict) -> None:
    print(f"Repo: {report['repo']}")
    print(f"Caveat: {report['caveat']}")
    if not report["releases"]:
        print("Releases: none")
    for release in report["releases"]:
        suffix = " (prerelease)" if release["prerelease"] else ""
        title = release["name"] or release["tag"]
        print(f"{release['tag']}{suffix}: {title} - {release['app_downloads']} app downloads")
        if not release["assets"]:
            print("  (no assets)")
        for asset in release["assets"]:
            kind = "app" if asset["app_artifact"] else "other"
            print(f"  {asset['name']}: {asset['asset_downloads']} downloads ({kind} asset)")
    print(f"Total app downloads: {report['total_app_downloads']}")
    if report["total_other_asset_downloads"]:
        print(f"Other asset downloads: {report['total_other_asset_downloads']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_REPO, type=parse_repo, help="GitHub repo as OWNER/REPO")
    parser.add_argument("--json", action="store_true", help="print JSON")
    args = parser.parse_args(argv)

    owner, repo_name = args.repo
    repo = f"{owner}/{repo_name}"
    try:
        report = aggregate(fetch_releases(owner, repo_name, os.environ.get("GITHUB_TOKEN")), repo)
    except RuntimeError as error:
        print(f"download-counts: {error}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
