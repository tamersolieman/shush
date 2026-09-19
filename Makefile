EXEC     := Shush
CONFIG   := debug

## Build products live OUTSIDE this directory, for the same reason the .app does.
##
## ~/Desktop is iCloud/file-provider synced, and the provider mutates files inside
## .build while the compiler is using them — producing "input file was modified during
## the build" on random object files, and occasionally a wedged swift-frontend stuck at
## 0% CPU. Moving the scratch path to ~/Library/Caches (never synced) removes the race.
SCRATCH  := $(HOME)/Library/Caches/ShushBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)

## The bundle is assembled and signed OUTSIDE this directory on purpose.
##
## This tree lives under ~/Desktop, which is iCloud/file-provider synced. The provider
## stamps com.apple.FinderInfo onto files inside an .app faster than we can strip them,
## and codesign hard-refuses anything carrying them ("resource fork, Finder information,
## or similar detritus not allowed"). `xattr -cr` immediately before signing is not enough
## — the provider re-stamps in between. Staging in ~/Library/Caches sidesteps it entirely.
STAGE    := $(HOME)/Library/Caches/ShushBuild
APPNAME  := Shush.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys the Accessibility grant to the code signature, so an ad-hoc signature — which
## changes on every build — makes the user re-grant after every `make`. Signing with a
## stable identity keeps the grant sticky across rebuilds. Prefers a real Developer ID if
## one's installed, otherwise falls back to the self-signed "Shush Local Dev" cert this repo
## sets up for local development (still stable across builds — TCC only needs the signature
## identity to not change, not to chain to a trusted CA). Falls back to ad-hoc ("-") if
## neither exists.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Shush Local Dev" | head -1 | sed -E 's/.*"(.*)".*/\1/')
endif
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

DMG := $(STAGE)/$(EXEC).dmg

## versions/$(EXEC).dmg is the only DMG pushed to GitHub — anyone can grab the latest
## release straight from the repo root of that folder. `make release` archives whatever
## was there before under versions/previous versions/, tagged with the version it shipped
## as (read from the archive's own VERSION marker, not the new build's Info.plist).
VERSIONS_DIR  := versions
ARCHIVE_DIR   := $(VERSIONS_DIR)/previous versions
RELEASE_DMG   := $(VERSIONS_DIR)/$(EXEC).dmg
VERSION_FILE  := $(VERSIONS_DIR)/.current_version
CURRENT_VER   := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

.PHONY: all build app run install clean icon dmg release

all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

## Regenerates AppIcon.icns from Resources/AppIcon-source.png (1024x1024). Not a
## dependency of `app` — the icon rarely changes.
icon:
	@rm -rf Resources/AppIcon.iconset
	@mkdir -p Resources/AppIcon.iconset
	@for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
	             "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" \
	             "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do \
	  set -- $$spec; \
	  sips -z $$1 $$1 Resources/AppIcon-source.png --out "Resources/AppIcon.iconset/$$2" >/dev/null; \
	done
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@cp Resources/BrandMark.png "$(CONTENTS)/Resources/"
	@cp Resources/StatusBarIcon.png "$(CONTENTS)/Resources/"
	@# Tajawal (Tamer Solieman Design System) — loaded via ATSApplicationFontsPath.
	@mkdir -p "$(CONTENTS)/Resources/Fonts"
	@cp Resources/Fonts/*.ttf "$(CONTENTS)/Resources/Fonts/"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Belt and braces: the staging dir isn't synced, but the copied binary can still carry
	@# xattrs inherited from the synced .build directory.
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

## Only ever targets the Shush executable — never the separate `shush` app.
run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Ad-hoc signatures change on every rebuild, which resets the Accessibility grant.
## Installing to /Applications keeps the path stable and makes re-granting a one-click fix.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@# $(BUNDLE) is an absolute staging path — the destination must use $(APPNAME) alone.
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

## Distributable disk image. Use `make dmg CONFIG=release` for a shipping build — plain
## `make dmg` packages whatever CONFIG is set to (debug by default).
dmg: app
	@rm -f "$(DMG)"
	@rm -rf "$(STAGE)/dmg-src"
	@mkdir -p "$(STAGE)/dmg-src"
	@cp -R "$(BUNDLE)" "$(STAGE)/dmg-src/$(APPNAME)"
	@ln -s /Applications "$(STAGE)/dmg-src/Applications"
	@hdiutil create -volname "$(EXEC)" -srcfolder "$(STAGE)/dmg-src" -ov -format UDZO "$(DMG)"
	@rm -rf "$(STAGE)/dmg-src"
	@echo "wrote $(DMG)"

## Build a release DMG and publish it to versions/. Use `make release CONFIG=release`
## for a shipping build — plain `make release` packages whatever CONFIG is set to.
release: dmg
	@mkdir -p "$(ARCHIVE_DIR)"
	@if [ -f "$(RELEASE_DMG)" ]; then \
		OLDVER=$$(cat "$(VERSION_FILE)" 2>/dev/null || echo unknown); \
		mv "$(RELEASE_DMG)" "$(ARCHIVE_DIR)/$(EXEC)-$$OLDVER.dmg"; \
		echo "archived previous build as $(ARCHIVE_DIR)/$(EXEC)-$$OLDVER.dmg"; \
	fi
	@cp "$(DMG)" "$(RELEASE_DMG)"
	@echo "$(CURRENT_VER)" > "$(VERSION_FILE)"
	@echo "published $(RELEASE_DMG)  [version $(CURRENT_VER)]"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
