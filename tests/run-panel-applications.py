#!/usr/bin/env python3
"""Run production app toggles/resolvers with Foundation and Preferences doubles."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]

def strip_imports(source):
    return re.sub(r'^#import .*\n', '', source, flags=re.M)

shared = (root / "DXShared.mm").read_text()
resolver = shared[shared.index("NSDictionary *preferencesLinkActionForSelector"):shared.index("BOOL preferencesIsConfiguredActionSelector")]
panel = (root / "DXGlobalPanel.m").read_text()
global_resolver = panel[panel.index("- (NSDictionary *)definition:"):panel.index("- (void)presentPanelSelector:")]
floating = (root / "DXFloatingAppSession.h").read_text()
floating = floating[floating.index("static inline BOOL DXActionUsesFloatingApp"):]

with tempfile.TemporaryDirectory(prefix="typex-panel-applications-") as directory:
    tmp = pathlib.Path(directory)
    (tmp / "PanelApplicationsProduction.h").write_text(
        '#import "PreferencesStatusBarStub.h"\n#import "DXPanelRegistry.h"\n#import "DXGlobalPanelPolicy.h"\n'
        + floating + '\nstatic NSDictionary *prefs;\n' + resolver
        + '\n@interface DXPrefsManager (Runtime)\n@property(nonatomic, readonly) NSDictionary *prefs;\n@end\n'
        + '@implementation DXPrefsManager (Runtime)\n- (NSDictionary *)prefs { return self.preferences; }\n@end\n'
        + '@interface RuntimePanel : NSObject\n- (NSDictionary *)definition:(NSString *)selector;\n@end\n'
        + '@implementation RuntimePanel\n' + global_resolver + '@end\n'
        + '@interface ATLApplicationSection : NSObject\n@property(nonatomic, copy) NSString *sectionName;\n@end\n'
        + '@implementation ATLApplicationSection\n@end\n'
        + '@interface ATLApplicationListMultiSelectionController : PSListController\n'
        + '- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section;\n'
        + '- (NSString *)localizedStringForString:(NSString *)string;\n@end\n'
        + '@implementation ATLApplicationListMultiSelectionController\n'
        + '- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section { return [PSSpecifier groupSpecifierWithName:section.sectionName]; }\n'
        + '- (NSString *)localizedStringForString:(NSString *)string { return string; }\n@end\n'
        + strip_imports((root / "typexprefs/DXPPanelApplicationsController.h").read_text())
        + strip_imports((root / "typexprefs/DXPPanelApplicationsController.m").read_text()))
    binary = tmp / "panel-applications"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(root), "-I", str(root / "tests"),
                    str(root / "tests/DXPanelApplicationTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
