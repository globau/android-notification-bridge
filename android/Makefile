export JAVA_HOME ?= /opt/homebrew/opt/openjdk
APP_ID := au.glob.notificationbridge
APK := app/build/outputs/apk/debug/app-debug.apk
DEVICE = $(shell adb devices | tail -n +2 | grep . | grep -v emulator | awk '{print $$1}')

.PHONY: build test run install clean

build:
	./gradlew assembleDebug

test:
	./gradlew testDebugUnitTest

run: install
	adb -s "$(DEVICE)" shell am start -n $(APP_ID)/.MainActivity

install: build
	adb -s "$(DEVICE)" install -r $(APK)

clean:
	./gradlew clean
