SHELL = /bin/bash

APP_NAME = JournlerMini
APP_BUNDLE = $(APP_NAME).app
APP_DIR = build/$(APP_BUNDLE)
APP_EXECUTABLE = $(APP_DIR)/Contents/MacOS/$(APP_NAME)
BUILD_SCRIPT = tools/build_minimal_app.sh
BUNDLE_ID = local.jnlr.JournlerMini

.PHONY: all clean build rebuild app-path reveal reset-accessibility

all: build

clean:
	rm -rf "$(APP_DIR)"

build:
	@"$(BUILD_SCRIPT)"

rebuild:
	$(MAKE) clean
	$(MAKE) build

app-path:
	@echo "$(PWD)/$(APP_DIR)"

reveal:
	@open -R "$(PWD)/$(APP_DIR)"

reset-accessibility:
	tccutil reset Accessibility $(BUNDLE_ID)
