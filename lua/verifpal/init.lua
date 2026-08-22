-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local config = require("verifpal.config")
local format = require("verifpal.format")
local lsp = require("verifpal.lsp")
local panel = require("verifpal.panel")

local M = {}

local augroup = vim.api.nvim_create_augroup("Verifpal", { clear = false })
local configured = false

local function resolve(bufnr)
	if not bufnr or bufnr == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return bufnr
end

function M.setup(opts)
	local problems = config.apply(opts)
	for _, problem in ipairs(problems) do
		vim.notify("Verifpal: " .. problem, vim.log.levels.WARN, { title = "Verifpal" })
	end
	configured = false
	M.start()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "verifpal" then
			vim.b[bufnr].verifpal_attached = nil
			M.attach(bufnr)
		end
	end
	return #problems == 0
end

function M.start()
	if configured then
		return true
	end
	configured = lsp.setup()
	return configured
end

function M.attach(bufnr)
	bufnr = resolve(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].verifpal_attached then
		return
	end
	vim.b[bufnr].verifpal_attached = true
	M.start()

	pcall(vim.api.nvim_clear_autocmds, { group = augroup, buffer = bufnr })

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			lsp.clear(bufnr)
		end,
	})

	if config.get("format_on_save") then
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = augroup,
			buffer = bufnr,
			desc = "Verifpal: format before writing",
			callback = function()
				format.format(bufnr, { silent = true })
			end,
		})
	end

	if config.get("verify_on_save") then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = augroup,
			buffer = bufnr,
			desc = "Verifpal: verify after writing",
			callback = function()
				M.verify(bufnr)
			end,
		})
	end
end

M.verify = lsp.verify
M.cancel = lsp.cancel
M.clear = lsp.clear
M.report = lsp.report
M.running = lsp.running
M.format = format.format

function M.hover()
	vim.lsp.buf.hover()
	return true
end

function M.statusline(bufnr)
	return lsp.status(bufnr or 0)
end

function M.results(bufnr)
	bufnr = resolve(bufnr)
	local report = lsp.report(bufnr)
	if report then
		panel.results(report, bufnr)
		return
	end
	if lsp.running(bufnr) then
		vim.notify(
			"Verifpal: an analysis is already running; results will not be long",
			vim.log.levels.INFO,
			{ title = "Verifpal" }
		)
		return
	end
	lsp.verify(bufnr, {
		on_done = function(fresh)
			if fresh then
				panel.results(fresh, bufnr)
			end
		end,
	})
end

function M.diagram(bufnr, raw)
	bufnr = resolve(bufnr)
	local ok = lsp.diagram(bufnr, function(err, result)
		if err or not result then
			vim.notify(
				"Verifpal: could not draw the diagram; the model may not parse",
				vim.log.levels.ERROR,
				{ title = "Verifpal" }
			)
			return
		end
		local text = raw and result.mermaid or result.readable
		local body = vim.split(vim.trim(text), "\n", { plain = true })
		local name = vim.api.nvim_buf_get_name(bufnr)
		name = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
		panel.diagram(body, name, raw)
	end)
	if not ok then
		vim.notify(
			"Verifpal: the language server is not attached to this buffer",
			vim.log.levels.ERROR,
			{ title = "Verifpal" }
		)
	end
end

function M.info()
	local lines = {}
	local cli = require("verifpal.cli")
	local path, err = cli.binary()
	if not path then
		lines[#lines + 1] = "verifpal: not found — " .. err
		lines[#lines + 1] = "Install it from https://verifpal.com, or set `path` in setup()."
		return lines
	end
	lines[#lines + 1] = "binary:  " .. path
	lines[#lines + 1] = "version: " .. (cli.version() or "unknown")
	local client = lsp.client(0)
	lines[#lines + 1] = "server:  " .. (client and "attached" or "not attached to this buffer")
	if not cli.supports_lsp() then
		lines[#lines + 1] = "This verifpal has no `lsp` subcommand. Upgrade to 1.1 or newer;"
		lines[#lines + 1] = "everything this plugin does now goes through the language server."
	end
	return lines
end

return M
