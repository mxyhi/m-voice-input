APP_NAME := MVoiceInput
EXECUTABLE := VoiceInputMenuBar
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
PLIST_PATH := Support/Info.plist
INSTALL_DIR ?= $(HOME)/Applications
CODESIGN_IDENTITY ?= -
SWIFT_CONFIGURATION ?= release

.PHONY: build run install clean test

build:
	swift build -c $(SWIFT_CONFIGURATION) --product $(EXECUTABLE)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)"
	cp ".build/arm64-apple-macosx/$(SWIFT_CONFIGURATION)/$(EXECUTABLE)" "$(MACOS_DIR)/$(EXECUTABLE)"
	cp "$(PLIST_PATH)" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --deep --sign "$(CODESIGN_IDENTITY)" --timestamp=none "$(APP_DIR)"

run: build
	open "$(APP_DIR)"

install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP_NAME).app"

test:
	swift run VoiceInputCoreTestRunner

clean:
	rm -rf .build "$(DIST_DIR)"
