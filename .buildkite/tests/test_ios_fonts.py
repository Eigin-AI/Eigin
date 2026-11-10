"""Verify optional font resources using the real XcodeGen tool on macOS."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("xcodegen") and shutil.which("plutil"),
                     "Font resource integration requires macOS with XcodeGen")
class FontResourceTests(unittest.TestCase):
    def test_project_generation_without_and_with_local_fonts(self):
        project = yaml.safe_load((ROOT / "src/eigin_ios/project.yml").read_text())
        targets = {}
        for name, target in project["targets"].items():
            fonts = [source for source in target.get("sources", [])
                     if (source if isinstance(source, str) else source.get("path", "")).startswith("Resources/Fonts")]
            if fonts:
                targets[name] = {"type": target["type"], "platform": target["platform"], "sources": fonts}
        self.assertTrue(targets, "Exercise font declarations from the application spec")
        for scenario in ("absent", "unrelated", "licensed"):
            present = scenario == "licensed"
            with self.subTest(fonts=scenario), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                if scenario != "absent":
                    filename = "FiveSerifText-Regular.otf" if present else "Unrelated.ttf"
                    font = root / "Resources/Fonts" / filename
                    font.parent.mkdir(parents=True)
                    font.write_bytes(b"Fixture resource; XcodeGen does not parse font contents.")
                spec = root / "project.yml"
                spec.write_text(yaml.safe_dump({"name": "FontResources", "targets": targets}))
                result = subprocess.run(["xcodegen", "generate", "--spec", str(spec)], cwd=root,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                pbx = root / "FontResources.xcodeproj/project.pbxproj"
                objects = json.loads(subprocess.check_output(
                    ["plutil", "-convert", "json", "-o", "-", str(pbx)], text=True))["objects"]
                for target in objects.values():
                    if target.get("isa") != "PBXNativeTarget":
                        continue
                    resources = [objects[file]["fileRef"]
                                 for phase in target["buildPhases"]
                                 if objects[phase]["isa"] == "PBXResourcesBuildPhase"
                                 for file in objects[phase]["files"]]
                    paths = [objects[ref]["path"] for ref in resources]
                    self.assertEqual("FiveSerifText-Regular.otf" in paths, present, target["name"])


if __name__ == "__main__":
    unittest.main()
