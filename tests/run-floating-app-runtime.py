#!/usr/bin/env python3
"""Production geometry and close method with process/UI doubles; no device claims."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "DXFloatingAppRuntime.mm").read_text()
with tempfile.TemporaryDirectory(prefix="typex-floating-runtime-") as tmp:
    tmp = pathlib.Path(tmp)
    # Compile the real termination flow; intercept the POSIX signal in the fixture.
    (tmp / "FloatingClose.inc").write_text(source[source.index("- (void)close {"):source.index("- (void)minimize {")])
    for name, extra in [("Geometry", ["-framework", "CoreGraphics"]),
                        ("Close", [str(root / "DXFloatingAppSession.m"), "-I", str(tmp)])]:
        binary = tmp / name
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                        "-framework", "Foundation", str(root / f"tests/DXFloatingApp{name}Tests.m"),
                        *extra, "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=15)
