.PHONY: icons test

test:
	$(MAKE) -C mac test
	$(MAKE) -C android test

# copies the designed icons from icons/ into each app
icons:
	cp icons/mac/AppIcon*.png mac/Resources/Assets.xcassets/AppIcon.appiconset/
	cp icons/mac/MenuBarIcon.png icons/mac/MenuBarIcon@2x.png mac/Resources/
	mkdir -p android/app/src/main/res
	cp -R icons/android/res/ android/app/src/main/res/
