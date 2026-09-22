ARCHS = arm64 arm64e

TARGET ?= iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TypeXPrefs

# Vendored AltList (com.opa334.altlist, MIT) — app-list controllers for the
# 生效应用/打开应用 pages; see AltList/README-TypeX-vendor.md.
TypeXPrefs_FILES = $(wildcard *.m) $(wildcard *.mm) $(wildcard AltList/*.m) ../DXPrefsManager.m ../DXShortcutsGenerator.m ../DXHelper.m ../DXAIEngine.m
TypeXPrefs_INSTALL_PATH = /Library/PreferenceBundles
TypeXPrefs_FRAMEWORKS = UIKit CoreGraphics SwiftUI MobileCoreServices
TypeXPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport
TypeXPrefs_CFLAGS = -fobjc-arc -Wno-tautological-pointer-compare
# sparkcolourpicker is no longer needed — using system UIColorPickerViewController
# TypeXPrefs_LIBRARIES = sparkcolourpicker

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp TypeXPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/TypeXPrefs.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/TypeX$(ECHO_END)
	$(ECHO_NOTHING)chmod 0777 $(THEOS_STAGING_DIR)/Library/TypeX$(ECHO_END)
