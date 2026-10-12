import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent

# Keep the test-injected key defines in lockstep with common.h (the 3.10.3
# duplicate-list drift trap).
defines = {
    "kLinkActionSelectorPrefix": "__typex_link_action_",
    "kCustomActionTypeKey": "type",
    "kCustomActionTypeOpenApp": "openapp",
    "kCustomActionFloatingKey": "floating",
}
common = (root / "common.h").read_text()
for name, value in defines.items():
    assert f'#define {name} @"{value}"' in common, f"{name} drifted from common.h"

header = (root / "typexprefs/DXPBatchOpenAppEntries.h").read_text()
helper = header[header.index("static inline NSArray"):]

with tempfile.TemporaryDirectory(prefix="typex-batch-apps-") as directory:
    tmp = pathlib.Path(directory)
    (tmp / "DXBatchOpenAppEntries.h").write_text(
        "#pragma once\n#import <Foundation/Foundation.h>\n"
        + "".join(f'#define {name} @"{value}"\n' for name, value in defines.items())
        + helper)
    binary = tmp / "batch-apps"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(root),
                    str(root / "tests/DXBatchOpenAppEntriesTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
