-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local M = {}

local function start(name)
	(vim.health.start or vim.health.report_start)(name)
end

local function ok(msg)
	(vim.health.ok or vim.health.report_ok)(msg)
end

local function warn(msg, advice)
	(vim.health.warn or vim.health.report_warn)(msg, advice)
end

local function err(msg, advice)
	(vim.health.error or vim.health.report_error)(msg, advice)
end

function M.check()
	start("verifpal.nvim")

	if vim.fn.has("nvim-0.12.4") == 1 then
		ok("Neovim 0.12.4 or newer")
	else
		err("Neovim 0.12.4 or newer is required", {
			"This plugin drives verifpal through its language server, and needs",
			"the vim.lsp folding and formatting behaviour that 0.12.4 settled.",
		})
		return
	end

	local cli = require("verifpal.cli")
	local path, why = cli.binary()
	if not path then
		err("verifpal not found: " .. (why or "unknown"), {
			"Install it from https://verifpal.com",
			"or set `path` in require('verifpal').setup().",
		})
		return
	end
	ok("binary: " .. path)

	local version = cli.version()
	if version then
		ok("version: " .. version)
	else
		warn("could not read the version")
	end

	if cli.supports_lsp() then
		ok("language server: `verifpal lsp` is available")
	else
		err("this verifpal has no `lsp` subcommand", {
			"Upgrade to Verifpal 1.1 or newer.",
			"Highlighting, hover, completion, diagnostics, formatting and",
			"analysis all come from the language server now.",
		})
		return
	end

	local clients = vim.lsp.get_clients({ name = "verifpal" })
	if #clients > 0 then
		ok(string.format("attached to %d buffer(s)", #clients[1].attached_buffers))
	else
		warn("not attached to any buffer", { "Open a .vp file." })
	end
end

return M
