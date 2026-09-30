#!/usr/bin/env python3
"""Test the production search/layout helpers and Chinese resource coverage."""
import json
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-settings-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "settings-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics",
                    str(root / "tests/DXSettingsSearchTests.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)

resources = root / "typexprefs/Resources"
def read_plist(path):
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))

localized = read_plist(resources / "zh-Hans.lproj/Root.strings")
missing = set()
def check_labels(value):
    if isinstance(value, dict):
        for key, text in value.items():
            if key in ("label", "title", "footerText") and isinstance(text, str) and re.fullmatch(r"[A-Z][A-Z0-9_]+", text):
                if not localized.get(text) or localized[text] == text:
                    missing.add(text)
            else:
                check_labels(text)
    elif isinstance(value, list):
        for item in value:
            check_labels(item)
for path in resources.glob("*.plist"):
    check_labels(read_plist(path))
assert not missing, f"untranslated settings labels: {sorted(missing)}"
assert localized["KEYBOARD_PANEL_SETTINGS"] == "滑动面板"
print("PASS: symbolic Settings labels have Chinese translations, including the Root panel entry")
