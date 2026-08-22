-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Reformatting a buffer with verifpal's canonical formatter.
---
--- The model is piped in on stdin rather than read from disk, so formatting
--- never saves the user's file behind their back and works on a buffer that
--- has never been written. Only the lines that actually changed are replaced,
--- which keeps marks, extmarks and the undo history proportional to the edit
--- instead of to the file.

local cli = require("verifpal.cli")
local config = require("verifpal.config")

local M = {}

--- Neovim reads 0 as "the current buffer"; every entry point here does too.
local function resolve(bufnr)
	if not bufnr or bufnr == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return bufnr
end

local function notify(msg, level)
	if config.get("notify") then
		if not tostring(msg):match("^Verifpal") then
			msg = "Verifpal: " .. msg
		end
		vim.notify(msg, level or vim.log.levels.INFO, { title = "Verifpal" })
	end
end

--- The narrowest line range whose replacement turns `old` into `new`.
--- Returns nil when the two are identical, so an already-canonical buffer is
--- left completely untouched: no edit, no undo entry, no 'modified' flag.
---@param old string[]
---@param new string[]
---@return integer|nil first, integer|nil last_old, string[]|nil replacement
function M.diff_range(old, new)
	local first = 1
	local max_prefix = math.min(#old, #new)
	while first <= max_prefix and old[first] == new[first] do
		first = first + 1
	end
	if first > #old and first > #new then
		return nil
	end
	local old_last, new_last = #old, #new
	while old_last >= first and new_last >= first and old[old_last] == new[new_last] do
		old_last = old_last - 1
		new_last = new_last - 1
	end
	local replacement = {}
	for i = first, new_last do
		replacement[#replacement + 1] = new[i]
	end
	return first, old_last, replacement
end

--- Apply formatted text to a buffer, keeping the cursor where the user left it.
---@param bufnr integer
---@param formatted string[]
---@return boolean changed
function M.apply(bufnr, formatted)
	local old = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local first, last, replacement = M.diff_range(old, formatted)
	if not first then
		return false
	end

	local views = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			views[win] = vim.api.nvim_win_call(win, vim.fn.winsaveview)
		end
	end

	vim.api.nvim_buf_set_lines(bufnr, first - 1, last, false, replacement)

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for win, view in pairs(views) do
		if vim.api.nvim_win_is_valid(win) then
			view.lnum = math.min(view.lnum, line_count)
			view.topline = math.min(view.topline, line_count)
			vim.api.nvim_win_call(win, function()
				vim.fn.winrestview(view)
			end)
		end
	end
	return true
end

--- Format the buffer.
---
--- Synchronous on purpose. `pretty` is a parse and a re-print, over in
--- milliseconds even on a large model, and a formatter that returns before it
--- has formatted cannot be composed — not with `:VerifpalFormat | write`, and
--- not with a BufWritePre hook.
---@param bufnr integer|nil
---@param opts table|nil { silent = boolean }
---@return boolean ok, boolean changed
function M.format(bufnr, opts)
	bufnr = resolve(bufnr)
	opts = opts or {}

	local path, err = cli.binary()
	if not path then
		notify(err, vim.log.levels.ERROR)
		return false, false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local features = cli.features()
	local timeout = math.min(config.get("timeout") or 15000, 30000)

	local result, scratch_dir, run_err
	if features.stdin then
		result, run_err = cli.run_sync({ "internal-json", "prettyPrint" }, {
			stdin = table.concat(lines, "\n") .. "\n",
			timeout = timeout,
		})
	else
		-- Older binaries only format a file on disk. Write a scratch copy
		-- rather than the user's own file: `:VerifpalFormat` is not a save.
		local dir = vim.fn.tempname()
		if vim.fn.mkdir(dir, "p") ~= 1 then
			notify("could not create a scratch directory", vim.log.levels.ERROR)
			return false, false
		end
		scratch_dir = dir
		local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
		if base == "" or not base:match("%.vp$") or #base > 64 then
			base = "buffer.vp"
		end
		local scratch = dir .. "/" .. base
		vim.fn.writefile(lines, scratch)
		result, run_err = cli.run_sync({ "pretty", scratch }, { timeout = timeout })
	end

	if scratch_dir then
		pcall(vim.fn.delete, scratch_dir, "rf")
	end

	if not result then
		notify(run_err or "formatting failed", vim.log.levels.ERROR)
		return false, false
	end
	if result.code ~= 0 then
		local text = vim.trim(result.stderr ~= "" and result.stderr or result.stdout)
		local parsed = cli.parse_error(text)
		notify(
			parsed and parsed.headline or (text ~= "" and text or "formatting failed"),
			vim.log.levels.ERROR
		)
		return false, false
	end
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false, false
	end

	local formatted = vim.split(result.stdout, "\n", { plain = true })
	-- The formatter terminates the file with a newline; splitting that leaves
	-- an empty final element that is not a line of the buffer.
	if #formatted > 0 and formatted[#formatted] == "" then
		table.remove(formatted)
	end
	if #formatted == 0 then
		notify("formatter returned nothing; buffer left unchanged", vim.log.levels.WARN)
		return false, false
	end

	local changed = M.apply(bufnr, formatted)
	if not opts.silent and not changed then
		vim.api.nvim_echo({ { "Verifpal: already formatted", "Comment" } }, false, {})
	end
	return true, changed
end

--- Is the buffer already in canonical form? Uses `pretty --check` where the
--- binary has it and falls back to comparing the formatted text otherwise.
---@return boolean|nil formatted, string|nil err
function M.is_formatted(bufnr)
	bufnr = resolve(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local features = cli.features()
	if not features.stdin then
		return nil, "this verifpal cannot format from stdin"
	end
	local result, err = cli.run_sync({ "internal-json", "prettyPrint" }, {
		stdin = table.concat(lines, "\n") .. "\n",
	})
	if not result or result.code ~= 0 then
		return nil, err or vim.trim(result and result.stderr or "")
	end
	local formatted = vim.split(result.stdout, "\n", { plain = true })
	if #formatted > 0 and formatted[#formatted] == "" then
		table.remove(formatted)
	end
	return M.diff_range(lines, formatted) == nil
end

return M
