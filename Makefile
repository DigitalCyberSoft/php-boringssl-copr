SHELL := /bin/bash

# Extension source (sibling directory)
EXT_SRC := $(realpath ../php-boringssl)

# Build directories
BUILD_DIR := $(CURDIR)/build
BSSL_SRC := $(BUILD_DIR)/boringssl
BSSL_BUILD := $(BSSL_SRC)/build
EXT_BUILD := $(BUILD_DIR)/extension
STATE_DIR := $(CURDIR)/.state

# PHP detection
PHP_CONFIG := $(shell command -v php-config 2>/dev/null)
PHP_VERSION := $(shell $(PHP_CONFIG) --version 2>/dev/null)
PHP_VERNUM := $(shell $(PHP_CONFIG) --vernum 2>/dev/null)
PHP_EXT_DIR := $(shell $(PHP_CONFIG) --extension-dir 2>/dev/null)
PHPIZE := $(shell command -v phpize 2>/dev/null)
NPROC := $(shell nproc 2>/dev/null || echo 4)

# BoringSSL
BSSL_REPO := https://boringssl.googlesource.com/boringssl

# State files
STATE_PHP := $(STATE_DIR)/php-version
STATE_BSSL := $(STATE_DIR)/boringssl-commit
STATE_BUILT := $(STATE_DIR)/last-build

.PHONY: all build boringssl extension install clean distclean \
        check-deps check-update status srpm

all: check-deps build

# --------------------------------------------------------------------------
# Dependency checks
# --------------------------------------------------------------------------

check-deps:
	@echo "=== Checking dependencies ==="
	@test -n "$(PHP_CONFIG)" || { echo "ERROR: php-config not found. Install php-devel."; exit 1; }
	@test -n "$(PHPIZE)" || { echo "ERROR: phpize not found. Install php-devel."; exit 1; }
	@command -v cmake >/dev/null || { echo "ERROR: cmake not found."; exit 1; }
	@command -v git >/dev/null || { echo "ERROR: git not found."; exit 1; }
	@command -v g++ >/dev/null || command -v c++ >/dev/null || { echo "ERROR: C++ compiler not found."; exit 1; }
	@test -d "$(EXT_SRC)" || { echo "ERROR: Extension source not found at $(EXT_SRC)"; exit 1; }
	@echo "  PHP $(PHP_VERSION) (API $(PHP_VERNUM))"
	@echo "  Extension dir: $(PHP_EXT_DIR)"
	@echo "  Extension src: $(EXT_SRC)"
	@echo "  OK"

# --------------------------------------------------------------------------
# BoringSSL
# --------------------------------------------------------------------------

boringssl: $(BSSL_BUILD)/libssl.a

$(BSSL_BUILD)/libssl.a: | $(BUILD_DIR) $(STATE_DIR)
	@echo "=== Fetching BoringSSL ==="
	@if [ -d "$(BSSL_SRC)/.git" ]; then \
		echo "  Updating existing checkout..."; \
		cd "$(BSSL_SRC)" && git fetch origin && git reset --hard origin/master; \
	else \
		echo "  Cloning fresh..."; \
		rm -rf "$(BSSL_SRC)"; \
		git clone --depth=1 "$(BSSL_REPO)" "$(BSSL_SRC)"; \
	fi
	@COMMIT=$$(cd "$(BSSL_SRC)" && git rev-parse HEAD); \
		echo "  Commit: $${COMMIT:0:12}"; \
		echo "$$COMMIT" > "$(STATE_BSSL)"
	@echo "=== Building BoringSSL ==="
	cd "$(BSSL_SRC)" && mkdir -p build && cd build && \
		cmake -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		      -DCMAKE_BUILD_TYPE=Release \
		      -GNinja .. 2>&1 | tail -3 && \
		ninja -j$(NPROC) ssl crypto 2>&1 | tail -5
	@echo "  libssl.a: $$(du -h $(BSSL_BUILD)/libssl.a | cut -f1)"
	@echo "  libcrypto.a: $$(du -h $(BSSL_BUILD)/libcrypto.a | cut -f1)"

# --------------------------------------------------------------------------
# PHP extension
# --------------------------------------------------------------------------

extension: $(EXT_BUILD)/modules/boringssl.so

$(EXT_BUILD)/modules/boringssl.so: $(BSSL_BUILD)/libssl.a | $(BUILD_DIR) $(STATE_DIR)
	@echo "=== Building PHP extension ==="
	@# Detect PHP version change
	@if [ -f "$(STATE_PHP)" ] && [ "$$(cat $(STATE_PHP))" != "$(PHP_VERSION)" ]; then \
		echo "  PHP version changed: $$(cat $(STATE_PHP)) -> $(PHP_VERSION)"; \
		echo "  Cleaning extension build..."; \
		rm -rf "$(EXT_BUILD)"; \
	fi
	@echo "$(PHP_VERSION)" > "$(STATE_PHP)"
	@# Copy source if needed
	@if [ ! -f "$(EXT_BUILD)/boringssl.c" ] || \
	    [ "$(EXT_SRC)/boringssl.c" -nt "$(EXT_BUILD)/boringssl.c" ] || \
	    [ "$(EXT_SRC)/php_boringssl.h" -nt "$(EXT_BUILD)/php_boringssl.h" ] || \
	    [ "$(EXT_SRC)/config.m4" -nt "$(EXT_BUILD)/config.m4" ]; then \
		echo "  Syncing extension source..."; \
		mkdir -p "$(EXT_BUILD)"; \
		cp "$(EXT_SRC)/boringssl.c" "$(EXT_BUILD)/"; \
		cp "$(EXT_SRC)/php_boringssl.h" "$(EXT_BUILD)/"; \
		cp "$(EXT_SRC)/config.m4" "$(EXT_BUILD)/"; \
		if [ -d "$(EXT_SRC)/tests" ]; then \
			cp -r "$(EXT_SRC)/tests" "$(EXT_BUILD)/"; \
		fi; \
	fi
	@# Point at our BoringSSL build
	cd "$(EXT_BUILD)" && \
		if [ ! -f configure ]; then \
			$(PHPIZE); \
		fi && \
		if [ ! -f Makefile ]; then \
			./configure --with-boringssl="$(BSSL_SRC)"; \
		fi && \
		make -j$(NPROC)
	@echo "  Built: $(EXT_BUILD)/modules/boringssl.so"
	@echo "  Size: $$(du -h $(EXT_BUILD)/modules/boringssl.so | cut -f1)"
	@date -u +"%Y-%m-%dT%H:%M:%SZ" > "$(STATE_BUILT)"

build: extension
	@echo ""
	@echo "=== Build complete ==="
	@echo "  PHP:       $(PHP_VERSION)"
	@echo "  BoringSSL: $$(cat $(STATE_BSSL) 2>/dev/null | head -c 12)"
	@echo "  Extension: $(EXT_BUILD)/modules/boringssl.so"
	@echo ""
	@echo "  Install with: make install"
	@echo "  Test with:    make test"

# --------------------------------------------------------------------------
# Install / Test
# --------------------------------------------------------------------------

install: $(EXT_BUILD)/modules/boringssl.so
	@echo "=== Installing ==="
	cd "$(EXT_BUILD)" && make install
	@if [ ! -f "$(shell $(PHP_CONFIG) --ini-dir 2>/dev/null)/40-boringssl.ini" ]; then \
		INI_DIR=$$($(PHP_CONFIG) --ini-dir 2>/dev/null || echo "/etc/php.d"); \
		echo "; Enable BoringSSL extension" > "$$INI_DIR/40-boringssl.ini"; \
		echo "extension=boringssl.so" >> "$$INI_DIR/40-boringssl.ini"; \
		echo "  Installed INI: $$INI_DIR/40-boringssl.ini"; \
	fi
	@echo "  Verify: php -m | grep boringssl"

test: $(EXT_BUILD)/modules/boringssl.so
	@echo "=== Running tests ==="
	cd "$(EXT_BUILD)" && \
		TEST_PHP_EXECUTABLE=$$(which php) \
		TEST_PHP_ARGS="-n -d extension=$$(pwd)/modules/boringssl.so" \
		REPORT_EXIT_STATUS=1 \
		php -n run-tests.php -q --show-diff

# --------------------------------------------------------------------------
# Version tracking / update detection
# --------------------------------------------------------------------------

check-update: | $(STATE_DIR)
	@echo "=== Checking for updates ==="
	@# Check PHP version
	@if [ -f "$(STATE_PHP)" ]; then \
		OLD_PHP=$$(cat "$(STATE_PHP)"); \
		if [ "$$OLD_PHP" != "$(PHP_VERSION)" ]; then \
			echo "  PHP UPDATED: $$OLD_PHP -> $(PHP_VERSION) (rebuild required)"; \
		else \
			echo "  PHP: $(PHP_VERSION) (unchanged)"; \
		fi; \
	else \
		echo "  PHP: $(PHP_VERSION) (no previous build)"; \
	fi
	@# Check BoringSSL
	@REMOTE=$$(git ls-remote "$(BSSL_REPO)" HEAD 2>/dev/null | cut -f1); \
	if [ -f "$(STATE_BSSL)" ]; then \
		LOCAL=$$(cat "$(STATE_BSSL)"); \
		if [ "$$LOCAL" != "$$REMOTE" ]; then \
			echo "  BoringSSL UPDATED: $${LOCAL:0:12} -> $${REMOTE:0:12} (rebuild available)"; \
		else \
			echo "  BoringSSL: $${LOCAL:0:12} (unchanged)"; \
		fi; \
	else \
		echo "  BoringSSL: $${REMOTE:0:12} (not yet built)"; \
	fi
	@# Check extension source
	@if [ -f "$(STATE_BUILT)" ]; then \
		echo "  Last build: $$(cat $(STATE_BUILT))"; \
	fi

status:
	@echo "=== Build Status ==="
	@echo "PHP version:     $(PHP_VERSION)"
	@echo "PHP API:         $(PHP_VERNUM)"
	@echo "Extension dir:   $(PHP_EXT_DIR)"
	@echo "Extension src:   $(EXT_SRC)"
	@echo -n "BoringSSL:       "; \
		if [ -f "$(STATE_BSSL)" ]; then \
			head -c 12 "$(STATE_BSSL)"; echo ""; \
		else echo "(not built)"; fi
	@echo -n "Built PHP ver:   "; \
		if [ -f "$(STATE_PHP)" ]; then \
			cat "$(STATE_PHP)"; \
		else echo "(not built)"; fi
	@echo -n "Last build:      "; \
		if [ -f "$(STATE_BUILT)" ]; then \
			cat "$(STATE_BUILT)"; \
		else echo "(never)"; fi
	@echo -n "Extension .so:   "; \
		if [ -f "$(EXT_BUILD)/modules/boringssl.so" ]; then \
			echo "OK ($$(du -h $(EXT_BUILD)/modules/boringssl.so | cut -f1))"; \
		else echo "(not built)"; fi

# --------------------------------------------------------------------------
# SRPM / COPR
# --------------------------------------------------------------------------

srpm:
	$(MAKE) -C .copr srpm outdir="$(CURDIR)"

# --------------------------------------------------------------------------
# Rebuild (force fresh BoringSSL + extension)
# --------------------------------------------------------------------------

rebuild: clean-extension
	@rm -f "$(BSSL_BUILD)/libssl.a"
	$(MAKE) build

clean-extension:
	rm -rf "$(EXT_BUILD)"
	rm -f "$(STATE_BUILT)"

# --------------------------------------------------------------------------
# Clean
# --------------------------------------------------------------------------

clean:
	rm -rf "$(EXT_BUILD)"
	rm -f "$(STATE_BUILT)"
	@echo "Extension build cleaned. BoringSSL kept (use 'make distclean' to remove)."

distclean:
	rm -rf "$(BUILD_DIR)" "$(STATE_DIR)"
	@echo "All build artifacts removed."

# --------------------------------------------------------------------------
# Directory creation
# --------------------------------------------------------------------------

$(BUILD_DIR):
	@mkdir -p "$@"

$(STATE_DIR):
	@mkdir -p "$@"
