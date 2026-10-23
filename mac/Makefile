APP := build/Notification Bridge.app
SWIFT_FLAGS := --disable-sandbox -c release

# first developer id in the keychain, falling back to ad-hoc; override with make SIGN_IDENTITY=...
SIGN_IDENTITY ?= $(or $(shell security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application[^"]*"' | tr -d '"'),-)

.PHONY: build test run install clean

build:
	swift build $(SWIFT_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build $(SWIFT_FLAGS) --show-bin-path)/NotificationBridge" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$(APP)/Contents/Resources/"
	xcrun actool Resources/Assets.xcassets --compile "$(APP)/Contents/Resources" --platform macosx \
		--minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist build/assets.plist >/dev/null
	codesign --force --options runtime --timestamp=none --sign "$(SIGN_IDENTITY)" "$(APP)"

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
