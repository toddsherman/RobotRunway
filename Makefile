.PHONY: all build install uninstall test clean

APP_NAME := RobotRunway
INSTALL_DIR := /Applications

all: build

build:
	@./build.sh

install: build
	@echo "📦 Installing $(APP_NAME).app to $(INSTALL_DIR)..."
	@cp -r build/$(APP_NAME).app $(INSTALL_DIR)/
	@echo "✅ Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@echo ""
	@echo "To run:"
	@echo "  open $(INSTALL_DIR)/$(APP_NAME).app"
	@echo ""
	@echo "To launch at login:"
	@echo "  System Settings → General → Login Items → add $(APP_NAME)"

uninstall:
	@if [ -d "$(INSTALL_DIR)/$(APP_NAME).app" ]; then \
		rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"; \
		echo "✅ Removed $(APP_NAME).app from $(INSTALL_DIR)"; \
	else \
		echo "⚠️  $(APP_NAME).app not found in $(INSTALL_DIR)"; \
	fi

test:
	@./test.sh

clean:
	@rm -rf build
	@echo "✅ Cleaned build directory"
