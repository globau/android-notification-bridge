export JAVA_HOME ?= /opt/homebrew/opt/openjdk
APP_ID := au.glob.notificationbridge
APK := app/build/outputs/apk/debug/app-debug.apk
DEVICE = $(shell adb devices | awk 'NR > 1 && $$2 == "device" && $$1 !~ /^emulator-/ { print $$1 }')
PROP = sed -nE 's/^[[:space:]]*$(1)([[:space:]]*[=:]|[[:space:]])[[:space:]]*//p' local.properties 2>/dev/null | tail -n 1
SDK_DIR := $(or $(shell $(call PROP,sdk\.dir)),$(ANDROID_HOME))
AVD ?= Samsung_S25

.PHONY: build release test run run-emulator start-emulator install clean check-env check-release check-device

build: check-env
	./gradlew assembleDebug

release: check-release
	./gradlew assembleRelease

test: check-env
	./gradlew testDebugUnitTest

run: install
	adb -s "$(DEVICE)" shell am start -n $(APP_ID)/.MainActivity

run-emulator: build start-emulator
	adb -e install -r $(APK)
	adb -e shell am start -n $(APP_ID)/.MainActivity

start-emulator: check-env
	@adb -e get-state >/dev/null 2>&1 || { \
		"$(SDK_DIR)/emulator/emulator" -avd $(AVD) >/dev/null 2>&1 & \
		adb -e wait-for-device && \
		until [ "$$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 1; done; }

install: check-device build
	adb -s "$(DEVICE)" install -r $(APK)

clean: check-env
	./gradlew clean

check-env:
	@"$(JAVA_HOME)/bin/java" -version >/dev/null 2>&1 || { echo "JAVA_HOME ($(JAVA_HOME)) is not a working jdk" >&2; exit 1; }
	@test -n "$(SDK_DIR)" || { echo "android sdk not configured: set ANDROID_HOME or sdk.dir in android/local.properties" >&2; exit 1; }
	@test -d "$(SDK_DIR)" || { echo "android sdk not found at $(SDK_DIR)" >&2; exit 1; }

check-release: check-env
	@test -f ../release-keystore.jks || { echo "release-keystore.jks not found" >&2; exit 1; }
	@test -n "$$($(call PROP,KEYSTORE_PASS))" || { echo "KEYSTORE_PASS not set in android/local.properties" >&2; exit 1; }
	@test -n "$$($(call PROP,KEY_PASS))" || { echo "KEY_PASS not set in android/local.properties" >&2; exit 1; }

check-device:
	@test $(words $(DEVICE)) -gt 0 || { echo "no authorised device connected via adb" >&2; exit 1; }
	@test $(words $(DEVICE)) -eq 1 || { echo "multiple devices connected via adb ($(DEVICE)): leave only one connected" >&2; exit 1; }
