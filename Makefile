# Chordware builds with Command Line Tools alone. No Xcode, no .xcodeproj,
# no third-party dependencies.

APP        := Chordware
BUNDLE_ID  := app.chordware.Chordware
VERSION    := 0.1.0
BUILD_DIR  := .build/release
DIST       := dist
APP_BUNDLE := $(DIST)/$(APP).app

.DEFAULT_GOAL := help
.PHONY: help build test run app icon dmg install clean cli

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build everything in release configuration
	@swift build -c release

test: ## Run the test suite
	# No `|| true`. Piping the build through grep swallowed its exit status, so
	# a compile failure ran the *previous* binary and reported it as a pass.
	@swift build --product chordware-selftest
	@./.build/debug/chordware-selftest

cli: build ## Build and print CLI usage
	@$(BUILD_DIR)/chordware help

clean: ## Remove build products
	@rm -rf .build $(DIST)

$(DIST):
	@mkdir -p $(DIST)

icon: | $(DIST) ## Generate the app icon
	@swift Tools/MakeIcon.swift $(DIST)/$(APP).icns

app: build icon | $(DIST) ## Assemble Chordware.app
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources $(APP_BUNDLE)/Contents/Helpers
	@cp $(BUILD_DIR)/ChordwareApp $(APP_BUNDLE)/Contents/MacOS/$(APP)
	# Helpers/, not MacOS/: macOS filesystems are case-insensitive, so a CLI at
	# MacOS/chordware overwrites the app binary at MacOS/Chordware.
	@cp $(BUILD_DIR)/chordware $(APP_BUNDLE)/Contents/Helpers/chordware
	@cp $(DIST)/$(APP).icns $(APP_BUNDLE)/Contents/Resources/$(APP).icns
	@Tools/make-plist.sh "$(APP)" "$(BUNDLE_ID)" "$(VERSION)" > $(APP_BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "  built $(APP_BUNDLE)"

run: install ## Build, install to /Applications, and relaunch
	@pkill -f "$(APP).app/Contents/MacOS/$(APP)" 2>/dev/null || true
	@sleep 1
	@open -a "/Applications/$(APP).app"
	@echo "  running /Applications/$(APP).app"

install: app ## Copy the app to /Applications
	@rm -rf /Applications/$(APP).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "  installed /Applications/$(APP).app"

dmg: app ## Package a distributable .dmg
	@hdiutil create -volname "$(APP)" -srcfolder $(APP_BUNDLE) -ov -format UDZO \
		$(DIST)/$(APP)-$(VERSION).dmg
	@echo "  built $(DIST)/$(APP)-$(VERSION).dmg"
