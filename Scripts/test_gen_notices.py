#!/usr/bin/env python3
"""Tests for Scripts/gen-notices.py. Run: python3 Scripts/test_gen_notices.py"""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gen_notices", HERE / "gen-notices.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class RealRepoTests(unittest.TestCase):
    def test_repo_has_no_problems(self):
        pins, packages, manual = gen.load_inputs()
        self.assertEqual(gen.problems(pins, packages, manual), [])

    def test_committed_outputs_are_current(self):
        stale = [str(p) for p, text in gen.outputs().items() if not p.is_file() or gen.read(p) != text]
        self.assertEqual(stale, [], "run Scripts/gen-notices.py")

    def test_every_resolved_package_is_in_the_notices(self):
        pins, packages, _ = gen.load_inputs()
        notices = gen.read(gen.ROOT / "THIRD_PARTY_NOTICES.md")
        for identity, pin in pins.items():
            self.assertIn(gen.package_url(pin), notices, identity)

    def test_app_json_lists_murmur_and_the_cc_by_models(self):
        data = json.loads(gen.read(gen.LEGAL / "notices.json"))
        titles = [s["title"] for s in data["sections"]]
        self.assertEqual(titles[0], "Murmur")
        self.assertIn("MIT License", data["sections"][0]["entries"][0]["text"])
        models = next(s for s in data["sections"] if s["title"] == "Models Murmur downloads")
        cc = [e for e in models["entries"] if e["license"] == "CC-BY-4.0"]
        self.assertTrue(cc)
        self.assertTrue(all("NVIDIA" in e["text"] for e in cc))


class FakeRepoTests(unittest.TestCase):
    """A minimal copy of the inputs, broken one way at a time."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        lic = self.root / "Licenses"
        (lic / "packages" / "alpha").mkdir(parents=True)
        (lic / "packages" / "alpha" / "LICENSE").write_text("MIT License\n\nCopyright (c) Alpha\n")
        (lic / "OFL-Font.txt").write_text("OFL text\n")
        (lic / "CC-BY-4.0.txt").write_text("CC text\n")
        fonts = self.root / "Fonts"
        fonts.mkdir()
        (fonts / "Font-OFL.txt").write_text("OFL text\n")
        (self.root / "LICENSE").write_text("MIT License\n\nCopyright (c) 2026 Someone\n")
        (self.root / "PRIVACY.md").write_text("# Privacy\n")
        self.write_resolved(["alpha"])
        self.packages = {"alpha": {"name": "Alpha", "use": "Things", "spdx": "MIT", "shipped": True, "files": ["LICENSE"]}}
        self.manual = {
            "fonts": [{"name": "Font", "version": "1", "url": "https://example.com/font", "spdx": "OFL-1.1",
                       "use": "Type", "files": ["OFL-Font.txt"], "bundled_copy": "Fonts/Font-OFL.txt"}],
            "models": [{"name": "Model", "repo": "org/model", "spdx": "CC-BY-4.0", "attribution": "By Org."}],
            "texts": [{"name": "CC BY 4.0", "spdx": "CC-BY-4.0", "file": "CC-BY-4.0.txt"}],
        }
        self.save()

    def tearDown(self):
        shutil.rmtree(self.root)

    def write_resolved(self, identities):
        pins = [{"identity": i, "location": f"https://github.com/example/{i}.git",
                 "state": {"version": "1.0.0", "revision": "abc"}} for i in identities]
        (self.root / "Package.resolved").write_text(json.dumps({"pins": pins, "version": 3}))

    def save(self):
        (self.root / "Licenses" / "packages.json").write_text(json.dumps(self.packages))
        (self.root / "Licenses" / "manual.json").write_text(json.dumps(self.manual))

    def found(self):
        return gen.problems(*gen.load_inputs(self.root), root=self.root)

    def test_clean_fake_repo_generates(self):
        self.assertEqual(self.found(), [])
        files = gen.outputs(self.root)
        notices = files[self.root / "THIRD_PARTY_NOTICES.md"]
        self.assertIn("### Alpha 1.0.0", notices)
        self.assertIn("https://github.com/example/alpha", notices)
        self.assertIn("Copyright (c) Alpha", notices)
        self.assertIn("By Org.", notices)

    def test_new_package_without_notice_fails(self):
        self.write_resolved(["alpha", "beta"])
        self.assertTrue(any("'beta'" in p and "doesn't describe" in p for p in self.found()))
        with self.assertRaises(gen.NoticeError):
            gen.outputs(self.root)

    def test_removed_package_fails(self):
        self.write_resolved([])
        self.assertTrue(any("no longer lists" in p for p in self.found()))

    def test_missing_license_file_fails(self):
        (self.root / "Licenses" / "packages" / "alpha" / "LICENSE").unlink()
        self.assertTrue(any("Missing license file Licenses/packages/alpha/LICENSE" in p for p in self.found()))

    def test_missing_field_fails(self):
        del self.packages["alpha"]["spdx"]
        self.save()
        self.assertTrue(any("has no 'spdx'" in p for p in self.found()))

    def test_font_license_drift_fails(self):
        (self.root / "Fonts" / "Font-OFL.txt").write_text("changed\n")
        self.assertTrue(any("differs from" in p for p in self.found()))

    def test_model_license_without_text_fails(self):
        self.manual["models"][0]["spdx"] = "Apache-2.0"
        self.save()
        self.assertTrue(any("Apache-2.0" in p and "texts" in p for p in self.found()))

    def test_build_only_package_is_listed_separately(self):
        self.packages["alpha"]["shipped"] = False
        self.save()
        notices = gen.outputs(self.root)[self.root / "THIRD_PARTY_NOTICES.md"]
        self.assertLess(notices.index("## Swift packages used only to build"), notices.index("### Alpha"))
        data = json.loads(gen.outputs(self.root)[self.root / "Sources/UI/Resources/Legal/notices.json"])
        packages = next(s for s in data["sections"] if s["title"] == "Swift packages")
        self.assertEqual(packages["entries"], [])

    def test_refresh_copies_from_checkouts(self):
        checkouts = self.root / "checkouts" / "Alpha"
        checkouts.mkdir(parents=True)
        (checkouts / "LICENSE").write_text("MIT License\n\nCopyright (c) Alpha 2\n")
        self.assertEqual(gen.refresh(self.root / "checkouts", self.root), [])
        self.assertIn("Alpha 2", gen.read(self.root / "Licenses" / "packages" / "alpha" / "LICENSE"))

    def test_refresh_reports_missing_checkout(self):
        (self.root / "checkouts").mkdir()
        self.assertEqual(len(gen.refresh(self.root / "checkouts", self.root)), 1)


class FenceTests(unittest.TestCase):
    def test_fence_is_longer_than_backtick_runs(self):
        self.assertEqual(gen.fence("plain"), "```")
        self.assertEqual(gen.fence("has ```` four"), "`````")


if __name__ == "__main__":
    unittest.main()
