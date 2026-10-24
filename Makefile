VERSION := $(shell cat VERSION)
DIST := build/Notification Bridge $(VERSION)
ZIP := build/notification-bridge-$(VERSION).zip

.PHONY: icons test dist release

test:
	$(MAKE) -C mac test
	$(MAKE) -C android test

# copies the designed icons from icons/ into each app
icons:
	cp icons/mac/AppIcon*.png mac/Resources/Assets.xcassets/AppIcon.appiconset/
	cp icons/mac/MenuBarIcon.png icons/mac/MenuBarIcon@2x.png mac/Resources/
	mkdir -p android/app/src/main/res
	cp -R icons/android/res/ android/app/src/main/res/

# both apps in one zip; ditto preserves the app bundle's signature.
# build outputs are moved, not copied, so no stray bundles confuse launchservices
dist:
	$(MAKE) -C mac notarise
	$(MAKE) -C android release
	rm -rf build
	mkdir -p "$(DIST)"
	mv "mac/build/Notification Bridge.app" "$(DIST)/"
	mv android/app/build/outputs/apk/release/app-release.apk "$(DIST)/Notification Bridge.apk"
	ditto -c -k --keepParent "$(DIST)" "$(ZIP)"
	rm -rf "$(DIST)"

# only publishes what's on github; the tag is created at the exact local commit
release:
	git fetch
	test -z "$$(git status --porcelain)" || { echo "cannot publish with uncommitted changes" >&2; exit 1; }
	test -z "$$(git log HEAD --not --remotes --format=%H)" || { echo "cannot publish with unpushed changes" >&2; exit 1; }
	test "$$(git rev-list --count HEAD..origin/main)" = 0 || { echo "cannot publish as local clone is behind origin" >&2; exit 1; }
	! gh release view "v$(VERSION)" >/dev/null 2>&1 || { echo "v$(VERSION) has already been published" >&2; exit 1; }
	$(MAKE) dist
	gh release create "v$(VERSION)" "$(ZIP)" --target "$$(git rev-parse HEAD)" \
		--title "Notification Bridge $(VERSION)" --generate-notes
