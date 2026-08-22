-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local config = require("verifpal.config")

local M = {}

local cache = {}

function M.reset()
	cache = {}
end

function M.binary()
	if cache.binary ~= nil then
		return cache.binary, cache.binary_error
	end
	local path = config.get("path") or "verifpal"
	local resolved = vim.fn.exepath(path)
	if resolved == "" and vim.fn.filereadable(path) == 1 then
		resolved = path
	end
	if resolved == "" then
		cache.binary = false
		cache.binary_error = string.format("`%s` is not on your $PATH", path)
		return nil, cache.binary_error
	end
	cache.binary = resolved
	return resolved
end

local function run(args)
	local path = M.binary()
	if not path then
		return nil
	end
	local result = vim.system(vim.list_extend({ path }, args), { text = true }):wait()
	return result
end

function M.version()
	if cache.version ~= nil then
		return cache.version or nil
	end
	local result = run({ "--version" })
	if not result or result.code ~= 0 then
		cache.version = false
		return nil
	end
	cache.version = vim.trim(result.stdout):match("%d+%.%d+%.%d+") or vim.trim(result.stdout)
	return cache.version
end

function M.supports_lsp()
	if cache.lsp ~= nil then
		return cache.lsp
	end
	local result = run({ "lsp", "--help" })
	cache.lsp = result ~= nil and result.code == 0
	return cache.lsp
end

return M
