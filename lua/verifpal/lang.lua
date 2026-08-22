-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Buffer-local language integration: hover, completion, folding, indenting.
---
--- Folding and indenting both read the model's own bracket structure rather
--- than matching line shapes, so a guarded value (`[ga]`) and a capability
--- parameter (`SIGN[forgeable]`) — brackets that open and close on one line —
--- do not create folds, and a `]` inside a comment does not close a block.

local docs = require("verifpal.docs")
local scan = require("verifpal.scan")

local M = {}

-- ---------------------------------------------------------------------------
-- Structure cache
-- ---------------------------------------------------------------------------

--- Depths are recomputed per change, not per line: 'foldexpr' is called once
--- for every line in the buffer, and rescanning inside it would make folding
--- quadratic.
local cache = {}

local function depths(bufnr)
	if not bufnr or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)
	local entry = cache[bufnr]
	if entry and entry.tick == tick then
		return entry.depths
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	entry = { tick = tick, depths = scan.depths(lines) }
	cache[bufnr] = entry
	return entry.depths
end

function M.forget(bufnr)
	cache[bufnr] = nil
end

-- ---------------------------------------------------------------------------
-- Folding
-- ---------------------------------------------------------------------------

--- 'foldexpr'. A line that leaves the buffer more deeply nested than it found
--- it opens a fold; one that leaves it shallower closes the fold it was in.
---@param lnum integer|nil 1-based; defaults to v:lnum
---@return string
function M.foldexpr(lnum)
	lnum = lnum or vim.v.lnum
	local d = depths()
	local line = d[lnum]
	if not line then
		return "0"
	end
	if line.finish > line.start then
		return ">" .. line.finish
	end
	if line.finish < line.start then
		return "<" .. line.start
	end
	return tostring(line.start)
end

-- ---------------------------------------------------------------------------
-- Indenting
-- ---------------------------------------------------------------------------

--- 'indentexpr'. One shiftwidth per open bracket, with a line that begins by
--- closing a block pulled back out to its opener's level.
---@param lnum integer|nil 1-based; defaults to v:lnum
---@return integer
function M.indentexpr(lnum)
	lnum = lnum or vim.v.lnum
	local bufnr = vim.api.nvim_get_current_buf()
	local d = depths(bufnr)
	local line = d[lnum]
	if not line then
		return 0
	end
	local level = line.start
	local text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
	if text:match("^%s*[%]%)]") then
		level = level - 1
	end
	local shift = vim.bo[bufnr].shiftwidth
	if shift == 0 then
		shift = vim.bo[bufnr].tabstop
	end
	return math.max(level, 0) * shift
end

-- ---------------------------------------------------------------------------
-- Hover
-- ---------------------------------------------------------------------------

--- Show documentation for the word under the cursor.
---@return boolean handled
function M.hover()
	local word = vim.fn.expand("<cword>")
	local entry, category = docs.lookup(word)
	if not entry then
		-- `nil` is punctuation-adjacent often enough that <cword> can miss it,
		-- and a bare `_` is a word Vim will not give us at all.
		local line = vim.api.nvim_get_current_line()
		local col = vim.api.nvim_win_get_cursor(0)[2] + 1
		if line:sub(col, col) == "_" then
			vim.lsp.util.open_floating_preview({
				"**_**",
				"",
				"`_ = HASH(m)`",
				"",
				"An anonymous constant. Use it where a primitive must be computed but its result is never referred to again; each `_` becomes a distinct unnamed constant.",
			}, "markdown", { focus = false, border = "rounded" })
			return true
		end
		return false
	end
	vim.lsp.util.open_floating_preview(
		docs.render(word, entry, category),
		"markdown",
		{ focus = false, border = "rounded", max_width = 80 }
	)
	return true
end

-- ---------------------------------------------------------------------------
-- Completion
-- ---------------------------------------------------------------------------

local DECLARATIONS = { "knows", "generates", "leaks" }
local QUALIFIERS = { "public", "private", "password" }
local BLOCKS = { "attacker", "principal", "phase", "queries" }

local function contains(list, want)
	for _, item in ipairs(list) do
		if item == want then
			return true
		end
	end
	return false
end

--- What kinds of word make sense at this position?
---
--- Context is read from the bracket structure, not guessed from the line: the
--- queries block wants query kinds, a primitive's parameter list wants
--- weakening assumptions, and `knows` wants a qualifier.
---@param bufnr integer
---@param lnum integer 1-based
---@param col integer 0-based, the start of the word being completed
---@return string context
function M.completion_context(bufnr, lnum, col)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local blanked = scan.blank_comments(lines)
	local before = (blanked[lnum] or ""):sub(1, col)

	local last_word = before:match("([%a_][%w_]*)%s*$")
	if last_word and contains(QUALIFIERS, last_word:lower()) then
		return "any"
	end
	if last_word and last_word:lower() == "knows" then
		return "qualifier"
	end

	-- Inside a primitive's capability parameter list: PRIMITIVE[<here>
	local open = before:match("([%a_][%w_]*)%s*%[[^%]%[]*$")
	if open and docs.primitives[open:upper()] then
		return "assumption"
	end

	local _, block = scan.queries(lines)
	if block and lnum - 1 >= block.start_lnum and lnum - 1 <= block.end_lnum then
		return "query"
	end

	local d = scan.depths(lines)
	if d[lnum] and d[lnum].start > 0 then
		return "principal"
	end
	return "top"
end

local function items_for(context)
	local all = docs.completions()
	local wanted = {}
	for _, item in ipairs(all) do
		local keep
		if context == "assumption" then
			keep = item.kind == "assumption"
		elseif context == "query" then
			keep = item.kind == "query"
		elseif context == "qualifier" then
			keep = item.kind == "keyword" and contains(QUALIFIERS, item.word)
		elseif context == "principal" then
			keep = item.kind == "primitive"
				or (item.kind == "keyword" and (contains(DECLARATIONS, item.word) or contains(
					QUALIFIERS,
					item.word
				)))
		elseif context == "top" then
			keep = item.kind == "keyword" and contains(BLOCKS, item.word)
		else
			keep = true
		end
		if keep then
			wanted[#wanted + 1] = item
		end
	end
	if #wanted == 0 then
		return all
	end
	return wanted
end

--- 'omnifunc'. Completes primitives, keywords, query kinds and weakening
--- assumptions, filtered by where the cursor is.
function M.omnifunc(findstart, base)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()

	if findstart == 1 then
		local start = cursor[2]
		while start > 0 and line:sub(start, start):match("[%w_]") do
			start = start - 1
		end
		return start
	end

	local context = M.completion_context(bufnr, cursor[1], cursor[2] - #base)
	local prefix = base:lower()
	local matches = {}
	for _, item in ipairs(items_for(context)) do
		if prefix == "" or item.word:lower():sub(1, #prefix) == prefix then
			matches[#matches + 1] = {
				word = item.word,
				kind = item.kind:sub(1, 1),
				menu = item.menu,
				info = item.info,
			}
		end
	end
	return matches
end

return M
