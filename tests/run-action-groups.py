import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent

# Keep the test-injected key defines in lockstep with common.h (the 3.10.3
# duplicate-list drift trap).
defines = {
    "kLinkActionGroupsKey": "linkactiongroups",
    "kCustomActionGroupKey": "group",
}
common = (root / "common.h").read_text()
for name, value in defines.items():
    assert f'#define {name} @"{value}"' in common, f"{name} drifted from common.h"

header = (root / "typexprefs/DXPActionGroups.h").read_text()
helpers = header[header.index("static inline NSString *DXActionGroupNormalizedName"):]

with tempfile.TemporaryDirectory(prefix="typex-action-groups-") as directory:
    tmp = pathlib.Path(directory)
    (tmp / "DXActionGroups.h").write_text(
        "#pragma once\n#import <Foundation/Foundation.h>\n"
        + "".join(f'#define {name} @"{value}"\n' for name, value in defines.items())
        + helpers)
    binary = tmp / "action-groups"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(root),
                    str(root / "tests/DXActionGroupsTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
