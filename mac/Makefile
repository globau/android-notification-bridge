APP := build/Notification Bridge.app
SWIFT_FLAGS := --disable-sandbox -c release
VERSION := $(shell cat ../VERSION)
BUILD_NUMBER := $(shell awk -F. '{ print $$1 * 10000 + $$2 * 100 + $$3 }' ../VERSION)

# first developer id in the keychain, falling back to ad-hoc; override with make SIGN_IDENTITY=...
SIGN_IDENTITY ?= $(or $(shell security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application[^"]*"' | tr -d '"'),-)
# notarisation needs a secure timestamp, which needs the network; skipped for local builds
TIMESTAMP := --timestamp=none
# stored with: xcrun notarytool store-credentials notarytool
NOTARY_PROFILE := notarytool

.PHONY: build notarise test run install clean

build:
	swift build $(SWIFT_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build $(SWIFT_FLAGS) --show-bin-path)/NotificationBridge" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(APP)/Contents/Info.plist"
	cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$(APP)/Contents/Resources/"
	xcrun actool Resources/Assets.xcassets --compile "$(APP)/Contents/Resources" --platform macosx \
		--minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist build/assets.plist >/dev/null
	codesign --force --options runtime $(TIMESTAMP) --sign "$(SIGN_IDENTITY)" "$(APP)"

# stapling fails unless notarisation was accepted
notarise: TIMESTAMP := --timestamp
notarise: build
	ditto -c -k --keepParent "$(APP)" build/notarise.zip
	xcrun notarytool submit build/notarise.zip --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple "$(APP)"
	rm build/notarise.zip

test:
	swift test --disable-sandbox

run: build
	open "$(APP)"

install: build
	rm -rf "$(HOME)/Applications/Notification Bridge.app"
	mkdir -p "$(HOME)/Applications"
	mv "$(APP)" "$(HOME)/Applications/"

clean:
	rm -rf .build build
