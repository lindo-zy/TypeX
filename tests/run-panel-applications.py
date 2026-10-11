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
app_list = (root / "typexprefs/AltList/ATLApplicationListControllerBase.m").read_text()
search = app_list[app_list.index("- (BOOL)shouldHideApplicationSpecifiers"):app_list.index("- (BOOL)shouldShowSubtitles")]

with tempfile.TemporaryDirectory(prefix="typex-panel-applications-") as directory:
    tmp = pathlib.Path(directory)
    # Extend the existing Preferences doubles only for this runner.
    stub = (root / "tests/PreferencesStatusBarStub.h").read_text()
    stub = stub.replace('@property(nonatomic, strong) id accessoryView;', '@property(nonatomic, strong) id accessoryView, editingAccessoryView;\n@property(nonatomic) BOOL showsReorderControl;')
    stub = stub.replace('@interface UITableView : NSObject', '@interface UITableView : NSObject\n@property(nonatomic) BOOL editing;\n- (void)setEditing:(BOOL)editing animated:(BOOL)animated;')
    stub = stub.replace('@implementation UITableView\n', '@implementation UITableView\n- (void)setEditing:(BOOL)editing animated:(BOOL)animated { (void)animated; self.editing = editing; }\n')
    stub = stub.replace('@property(nonatomic, strong) PSSpecifier *specifier;', '@property(nonatomic, strong) PSSpecifier *specifier;\n@property(nonatomic, strong) UITableView *table;')
    (tmp / "PreferencesStatusBarStub.h").write_text(stub)
    (tmp / "PanelApplicationsSearch.inc").write_text(search)
    (tmp / "PanelApplicationsProduction.h").write_text(
        '#import "PreferencesStatusBarStub.h"\n#import "DXPanelRegistry.h"\n#import "DXGlobalPanelPolicy.h"\n'
        + floating + '\nstatic NSDictionary *prefs;\n' + resolver
        + '\n@interface DXPrefsManager (Runtime)\n@property(nonatomic, readonly) NSDictionary *prefs;\n@end\n'
        + '@implementation DXPrefsManager (Runtime)\n- (NSDictionary *)prefs { return self.preferences; }\n@end\n'
        + '@interface RuntimePanel : NSObject\n- (NSDictionary *)definition:(NSString *)selector;\n@end\n'
        + '@implementation RuntimePanel\n' + global_resolver + '@end\n'
        + '#import "PanelApplicationsListStub.h"\n'
        + strip_imports((root / "typexprefs/DXPPanelApplicationsController.h").read_text())
        + strip_imports((root / "typexprefs/DXPPanelApplicationsController.m").read_text()))
    for test in ("DXPanelApplicationTests", "DXPanelApplicationOrderingTests"):
        binary = tmp / test
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                        "-framework", "Foundation", "-I", str(tmp), "-I", str(root), "-I", str(root / "tests"),
                        str(root / f"tests/{test}.m"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=20)
