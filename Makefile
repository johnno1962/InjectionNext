# InjectionNext Makefile

XCODE_PROJECT ?= App/InjectionNext.xcodeproj
XCODE_SCHEME  ?= InjectionNext
XCODE_CONFIG  ?= Debug
DERIVED_DATA  ?= build
APP_NAME      ?= InjectionNext
APP_PATH      := $(DERIVED_DATA)/Build/Products/$(XCODE_CONFIG)/$(APP_NAME).app

.PHONY: all build-app run open clean kill help move-app

all: build-app

help:
	@echo "Targets:"
	@echo "  build-app   Build $(APP_NAME).app ($(XCODE_CONFIG))"
	@echo "  run         Build then launch the app"
	@echo "  open        Open the already-built app"
	@echo "  kill        Kill any running $(APP_NAME) process"
	@echo "  clean       Remove derived data ($(DERIVED_DATA))"

kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.2

build-app: kill
	@echo "==> Building $(APP_NAME).app ($(XCODE_CONFIG))..."
	xcodebuild \
		-project $(XCODE_PROJECT) \
		-scheme $(XCODE_SCHEME) \
		-configuration $(XCODE_CONFIG) \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED_DATA) \
		build \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		-quiet
	@echo "==> Build complete: $(APP_PATH)"

move-app: build-app kill
	@echo "==> Installing to /Applications..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_PATH) /Applications/

open: move-app
	@echo "==> Opening $(APP_PATH)..."
	@open /Applications/InjectionNext.app

run: build-app open

clean:
	@echo "==> Cleaning $(DERIVED_DATA)..."
	@rm -rf $(DERIVED_DATA)
