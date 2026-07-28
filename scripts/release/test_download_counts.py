#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("download-counts.py")
SPEC = importlib.util.spec_from_file_location("download_counts", MODULE_PATH)
download_counts = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(download_counts)


class DownloadCountsTests(unittest.TestCase):
    def test_aggregate_skips_drafts_includes_prereleases_and_sums_assets(self):
        report = download_counts.aggregate(
            [
                {
                    "tag_name": "draft",
                    "name": "Draft",
                    "draft": True,
                    "prerelease": False,
                    "assets": [{"name": "hidden.dmg", "download_count": 99}],
                },
                {
                    "tag_name": "v1.0.0-beta",
                    "name": "Beta",
                    "draft": False,
                    "prerelease": True,
                    "assets": [
                        {"name": "Abendrot.dmg", "download_count": 2},
                        {"name": "Abendrot.zip", "download_count": 4},
                        {"name": "appcast.xml", "download_count": 3},
                    ],
                },
                {
                    "tag_name": "v1.0.0",
                    "name": "Stable",
                    "draft": False,
                    "prerelease": False,
                    "assets": [{"name": "Abendrot.dmg", "download_count": 5}],
                },
            ],
            "owner/repo",
        )

        self.assertEqual(report["repo"], "owner/repo")
        self.assertEqual(report["caveat"], download_counts.CAVEAT)
        self.assertEqual(report["total_app_downloads"], 7)
        self.assertEqual(report["total_other_asset_downloads"], 7)
        self.assertEqual([release["tag"] for release in report["releases"]], ["v1.0.0-beta", "v1.0.0"])
        self.assertTrue(report["releases"][0]["prerelease"])
        self.assertEqual(report["releases"][0]["app_downloads"], 2)
        self.assertEqual(report["releases"][0]["other_asset_downloads"], 7)
        self.assertFalse(report["releases"][0]["assets"][1]["app_artifact"])
        self.assertEqual(report["releases"][1]["assets"][0]["asset_downloads"], 5)


if __name__ == "__main__":
    unittest.main()
