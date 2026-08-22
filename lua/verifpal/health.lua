-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- `:checkhealth verifpal`.

local M = {}

local start = vim.health.start
local ok = vim.health.ok
local warn = vim.health.warn
local error = vim.health.error
local info = vim.health.info

--- Features that only exist in a newer verifpal than a user may have. Each
--- names what the plugin loses without it, so a warning is actionable rather
--- than a version number to compare by hand.
local OPTIONAL = {
	{
		key = "json",
		what = "verify --format json",
		lost = "narrated attack traces, timings and the results panel's detail",
	},
	{
		key = "stdin",
		what = "the internal-json interface",
		lost = "formatting and diagramming an unsaved buffer",
	},
	{ key = "sessions", what = "verify --sessions", lost = "choosing the session count" },
}

--- Present but not needed: the plugin draws diagrams through `internal-json`,
--- so reporting the absence of `diagram` as a warning would be telling the
--- user to act on something that costs them nothing.
local INFORMATIONAL = {
	{ key = "diagram", what = "the diagram subcommand" },
	{ key = "quiet", what = "verify --quiet" },
	{ key = "color", what = "verify --color" },
}

function M.check()
	start("verifpal.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		ok("Neovim " .. tostring(vim.version()))
	else
		error("Neovim 0.10 or newer is required (vim.system).")
		return
	end

	local config = require("verifpal.config")
	local cli = require("verifpal.cli")

	local path, err = cli.binary()
	if not path then
		error("verifpal binary: " .. err, {
			"Install Verifpal from https://verifpal.com",
			'Or point the plugin at it: require("verifpal").setup({ path = "/path/to/verifpal" })',
		})
		return
	end
	ok("verifpal binary: " .. path)

	local version = cli.version()
	if version then
		ok("version: " .. version)
	else
		warn("could not read a version from `verifpal --version`.")
	end

	local features = cli.features()
	for _, feature in ipairs(OPTIONAL) do
		if features[feature.key] then
			ok(feature.what .. ": supported")
		else
			warn(
				string.format("%s: not supported by this verifpal", feature.what),
				{ "Without it: " .. feature.lost, "Upgrade at https://verifpal.com" }
			)
		end
	end
	for _, feature in ipairs(INFORMATIONAL) do
		info(
			string.format(
				"%s: %s",
				feature.what,
				features[feature.key] and "supported" or "not supported (not needed)"
			)
		)
	end

	start("verifpal.nvim configuration")
	info("path: " .. tostring(config.get("path")))
	info("sessions: " .. tostring(config.get("sessions") or "verifpal's default"))
	info("timeout: " .. tostring(config.get("timeout")) .. " ms")
	info("verify_on_save: " .. tostring(config.get("verify_on_save")))
	info("format_on_save: " .. tostring(config.get("format_on_save")))

	local hover = config.get("hover_key")
	if hover then
		info("hover key: " .. hover)
	else
		info("hover key: disabled")
	end

	start("verifpal.nvim language data")
	local docs = require("verifpal.docs")
	local count = vim.tbl_count(docs.primitives)
	if count == 25 then
		ok(count .. " primitives documented")
	else
		warn(string.format("%d primitives documented; verifpal defines 25", count))
	end
end

return M
