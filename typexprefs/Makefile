ARCHS = arm64 arm64e

TARGET ?= iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TypeXPrefs

TypeXPrefs_FILES = $(wildcard *.m) $(wildcard *.mm) ../DXPrefsManager.m ../DXShortcutsGenerator.m ../DXHelper.m
TypeXPrefs_INSTALL_PATH = /Library/PreferenceBundles
TypeXPrefs_FRAMEWORKS = UIKit CoreGraphics SwiftUI
TypeXPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport
TypeXPrefs_CFLAGS = -fobjc-arc
# sparkcolourpicker is no longer needed — using system UIColorPickerViewController
# TypeXPrefs_LIBRARIES = sparkcolourpicker

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp TypeXPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/TypeXPrefs.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/TypeX$(ECHO_END)
	$(ECHO_NOTHING)chmod 0777 $(THEOS_STAGING_DIR)/Library/TypeX$(ECHO_END)
