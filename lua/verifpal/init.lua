-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Neovim support for Verifpal, the symbolic formal verification tool for
--- cryptographic protocols: https://verifpal.com
---
--- `setup()` is optional. Everything here works from defaults, because the
--- buffer-local half is attached by `ftplugin/verifpal.vim` and the commands
--- are registered by `plugin/verifpal.lua` — a user who only wants syntax and
--- `:VerifpalVerify` should not have to write configuration to get it.

local cli = require("verifpal.cli")
local config = require("verifpal.config")
local format = require("verifpal.format")
local lang = require("verifpal.lang")
local panel = require("verifpal.panel")
local verify = require("verifpal.verify")

local M = {}

local augroup = vim.api.nvim_create_augroup("Verifpal", { clear = false })

--- Neovim reads 0 as "the current buffer"; every entry point here does too.
local function resolve(bufnr)
	if not bufnr or bufnr == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return bufnr
end

--- Configure the plugin. Safe to call more than once; the last call wins.
---@param opts table|nil
function M.setup(opts)
	local problems = config.apply(opts)
	cli.reset()
	for _, problem in ipairs(problems) do
		vim.notify("Verifpal: " .. problem, vim.log.levels.WARN, { title = "Verifpal" })
	end
	-- A buffer already open when setup runs never sees another FileType event,
	-- so re-attach it rather than leaving it on the previous configuration.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "verifpal" then
			vim.b[bufnr].verifpal_attached = nil
			M.attach(bufnr)
		end
	end
	return #problems == 0
end

--- Set up one `.vp` buffer. Called from ftplugin, so it runs whether or not
--- setup() ever did.
---@param bufnr integer|nil
function M.attach(bufnr)
	bufnr = resolve(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].verifpal_attached then
		return
	end
	vim.b[bufnr].verifpal_attached = true

	-- setup() re-attaches buffers that are already open, so anything attach
	-- registers has to be idempotent. Autocmds are not: a second BufWritePre
	-- in the same group would format the buffer twice on every write.
	pcall(vim.api.nvim_clear_autocmds, { group = augroup, buffer = bufnr })

	local previous_key = vim.b[bufnr].verifpal_hover_key
	if previous_key then
		pcall(vim.keymap.del, "n", previous_key, { buffer = bufnr })
		vim.b[bufnr].verifpal_hover_key = nil
	end

	local hover_key = config.get("hover_key")
	if hover_key then
		vim.b[bufnr].verifpal_hover_key = hover_key
		vim.keymap.set("n", hover_key, function()
			if not lang.hover() then
				-- Nothing of ours under the cursor: fall through to whatever
				-- the key would otherwise have done rather than eating it.
				local keys = vim.api.nvim_replace_termcodes(hover_key, true, false, true)
				vim.api.nvim_feedkeys(keys, "n", false)
			end
		end, { buffer = bufnr, desc = "Verifpal: documentation for the word under the cursor" })
	end

	if config.get("completion") then
		vim.bo[bufnr].omnifunc = "v:lua.require'verifpal.lang'.omnifunc"
	end

	-- Folding is window-local. Setting it with :setlocal from the FileType
	-- event is what makes a later split inherit it, the same way every
	-- ftplugin does; assigning through vim.wo would bind it to whichever
	-- window happened to be current.
	if config.get("fold") and vim.api.nvim_win_get_buf(0) == bufnr then
		vim.cmd([[
			setlocal foldmethod=expr
			setlocal foldexpr=v:lua.require'verifpal.lang'.foldexpr()
			setlocal foldlevel=99
		]])
	end
	if config.get("indent") then
		vim.bo[bufnr].indentexpr = "v:lua.require'verifpal.lang'.indentexpr()"
		vim.bo[bufnr].indentkeys = "0],0),o,O,!^F"
	end

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			lang.forget(bufnr)
			verify.clear(bufnr)
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
				verify.verify(bufnr, { silent = false })
			end,
		})
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

M.verify = verify.verify
M.cancel = verify.cancel
M.clear = verify.clear
M.format = format.format
M.hover = lang.hover
M.report = verify.report

--- A short verification status for a statusline: a spinner while an analysis
--- runs, the verdict once it has finished, and "" when there is nothing to say.
---@param bufnr integer|nil
---@return string
function M.statusline(bufnr)
	return verify.status(bufnr)
end

--- Open the results panel, verifying first if there is nothing to show.
function M.results(bufnr)
	bufnr = resolve(bufnr)
	local report = verify.report(bufnr)
	if report then
		panel.results(report, bufnr)
		return
	end
	if verify.running(bufnr) then
		vim.notify(
			"Verifpal: an analysis is already running; results will not be long",
			vim.log.levels.INFO,
			{ title = "Verifpal" }
		)
		return
	end
	verify.verify(bufnr, {
		on_done = function(fresh)
			panel.results(fresh, bufnr)
		end,
	})
end

--- Open the protocol's sequence diagram.
---@param bufnr integer|nil
---@param raw boolean|nil show verifpal's mermaid source rather than the
---                      readable rendering
function M.diagram(bufnr, raw)
	bufnr = resolve(bufnr)
	local features = cli.features()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local result, err

	if features.stdin then
		result, err = cli.run_sync({ "internal-json", "prettyDiagram" }, {
			stdin = table.concat(lines, "\n") .. "\n",
		})
	else
		local name = vim.api.nvim_buf_get_name(bufnr)
		if name == "" then
			vim.notify(
				"Verifpal: this verifpal needs the model on disk to draw a diagram",
				vim.log.levels.ERROR,
				{ title = "Verifpal" }
			)
			return
		end
		result, err = cli.run_sync({ "diagram", name })
	end

	if not result then
		vim.notify("Verifpal: " .. (err or "could not draw the diagram"), vim.log.levels.ERROR, {
			title = "Verifpal",
		})
		return
	end
	if result.code ~= 0 then
		local text = vim.trim(result.stderr ~= "" and result.stderr or result.stdout)
		local parsed = cli.parse_error(text)
		vim.notify(
			"Verifpal: " .. (parsed and parsed.headline or text),
			vim.log.levels.ERROR,
			{ title = "Verifpal" }
		)
		return
	end

	local body = vim.split(vim.trim(result.stdout), "\n", { plain = true })
	if raw and body[1] ~= "sequenceDiagram" then
		table.insert(body, 1, "sequenceDiagram")
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	name = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
	panel.diagram(body, name, raw)
end

--- What the plugin found and what it can use it for.
---@return string[]
function M.info()
	local lines = {}
	local path, err = cli.binary()
	if not path then
		lines[#lines + 1] = "verifpal: not found — " .. err
		lines[#lines + 1] = "Install it from https://verifpal.com, or set `path` in setup()."
		return lines
	end
	lines[#lines + 1] = "binary:  " .. path
	lines[#lines + 1] = "version: " .. (cli.version() or "unknown")
	local features = cli.features()
	local names = {}
	for _, name in ipairs({ "json", "sessions", "quiet", "color", "diagram", "stdin" }) do
		names[#names + 1] = name .. "=" .. tostring(features[name] == true)
	end
	lines[#lines + 1] = "supports: " .. table.concat(names, "  ")
	if not features.json then
		lines[#lines + 1] =
			"This verifpal predates `verify --format json`: verdicts are exact, but"
		lines[#lines + 1] = "there are no narrated attack traces. Upgrading enables them."
	end
	return lines
end

return M
