# SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
# SPDX-License-Identifier: GPL-3.0-only

NVIM ?= nvim

.PHONY: test check fmt docs all

all: check test

## Run the headless test suite. VERIFPAL_BIN=... picks the binary to test
## against; without one, the tests that need it skip themselves.
test:
	$(NVIM) --headless -u tests/minimal.lua -l tests/run.lua

## Lint and format-check the Lua, where the tools are installed.
check:
	@if command -v luacheck >/dev/null 2>&1; then \
		luacheck lua tests; \
	else \
		echo "luacheck not installed, skipping"; \
	fi
	@if command -v stylua >/dev/null 2>&1; then \
		stylua --check lua tests; \
	else \
		echo "stylua not installed, skipping"; \
	fi

fmt:
	stylua lua tests

## Regenerate the help tags, as a plugin manager would.
docs:
	$(NVIM) --headless -c "helptags doc" -c "qa!"
