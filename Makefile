.DEFAULT_GOAL := help

# Pinned tools from .mise.toml; falls back to PATH when mise is not installed.
MISE := $(shell command -v mise 2>/dev/null)
SWIFTLINT := $(if $(MISE),mise exec -- swiftlint,swiftlint)

.PHONY: help bootstrap lint layers test build ci install

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

bootstrap: ## Install pinned tools (requires mise)
	mise install

lint: ## SwiftLint, strict
	$(SWIFTLINT) lint --strict --quiet

layers: ## Layer dependency check, fails on violations
	scripts/check-layers.sh --strict

test: ## Full test suite
	swift test

build: ## Release build
	swift build -c release

ci: lint layers test build ## Everything CI runs

install: ## Put this checkout's release build on PATH
	scripts/install-local.sh
