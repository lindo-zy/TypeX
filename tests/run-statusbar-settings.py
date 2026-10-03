#!/usr/bin/env python3
"""Compile the production Settings controller against narrow Foundation doubles.

Exercises configured row actions, binding persistence and editor callbacks;
native Preferences dispatch and UIKit navigation still require iOS checks.
"""
import json
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
common = (root / "common.h").read_text()
defines = "\n".join(re.findall(r'^#define (?:kLinkActionskey|kLinkActionSelectorPrefix|kCustomActionTypeURLScheme|kCustomActionTypeOpenApp|kCustomActionTypeShortcut|kCustomActionTypeSystem) @"[^"\n]*"$', common, re.M))
selector_start = common.index("static inline BOOL DXIsLinkActionSelector")
selector_helper = common[selector_start:common.index("\n}", selector_start) + 2]
source = (root / "typexprefs/DXPStatusBarGestureController.m").read_text()
source = re.sub(r'^#import .*\n', '', source, flags=re.M)
with tempfile.TemporaryDirectory(prefix="typex-statusbar-settings-") as temporary:
    tmp = pathlib.Path(temporary)
    (tmp / "StatusBarSettingsProduction.h").write_text(
        '#import "PreferencesStatusBarStub.h"\n#import "DXStatusBarGesturePolicy.h"\n#import "DXGlobalPanelPolicy.h"\n'
        + defines + '\n#define bundlePath @' + json.dumps(str(root / "typexprefs/Resources")) + '\n'
        + selector_helper + '\n' + source)
    binary = tmp / "statusbar-settings-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(root), "-I", str(root / "tests"),
                    str(root / "tests/DXStatusBarSettingsTests.m"), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
    if result.returncode:
        print(result.stderr)
    result.check_returncode()
    print(result.stdout, end="")
