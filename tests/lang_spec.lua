-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local lang = require("verifpal.lang")

local function open(name)
	local bufnr = T.buffer(T.model(name), name)
	return bufnr
end

T.test("lang: folds open on a block header and close on its bracket", function()
	local bufnr = open("plain.vp")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local levels = {}
	for i = 1, #lines do
		levels[i] = lang.foldexpr(i)
	end
	for i, line in ipairs(lines) do
		if line:match("^principal%s") or line:match("^queries%[") then
			T.eq(levels[i], ">1", "line " .. i .. " opens a fold: " .. line)
		elseif line == "]" then
			T.eq(levels[i], "<1", "line " .. i .. " closes a fold")
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: a guarded value does not open a fold", function()
	local bufnr = open("tricky.vp")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:match("^Alice %-> Bob: %[ga%], e") then
			T.eq(lang.foldexpr(i), "0", "a guard opens and closes on one line")
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: indent is one shiftwidth per open block", function()
	local bufnr = open("plain.vp")
	vim.bo[bufnr].shiftwidth = 4
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:match("^\t%S") then
			T.eq(lang.indentexpr(i), 4, "line " .. i .. " sits one level in")
		elseif line == "]" then
			T.eq(lang.indentexpr(i), 0, "a closing bracket returns to its opener")
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: indent falls back to tabstop when shiftwidth is zero", function()
	local bufnr = open("plain.vp")
	vim.bo[bufnr].shiftwidth = 0
	vim.bo[bufnr].tabstop = 4
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		if line:match("^\t%S") then
			T.eq(lang.indentexpr(i), 4)
			break
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: completion offers query kinds inside the queries block", function()
	local bufnr = open("tricky.vp")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local queries_line
	for i, line in ipairs(lines) do
		if line:match("^%s*confidentiality%?") then
			queries_line = i
			break
		end
	end
	T.ok(queries_line ~= nil, "found a query line")
	T.eq(lang.completion_context(bufnr, queries_line, 1), "query")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: completion offers weakening assumptions inside a parameter list", function()
	local bufnr = T.buffer({
		"attacker[active]",
		"principal Alice[",
		"\tknows private k",
		"\te = AEAD_ENC[",
		"]",
	}, "ctx.vp")
	T.eq(lang.completion_context(bufnr, 4, #"\te = AEAD_ENC["), "assumption")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: completion offers qualifiers after `knows`", function()
	local bufnr = T.buffer({ "principal Alice[", "\tknows ", "]" }, "ctx.vp")
	T.eq(lang.completion_context(bufnr, 2, #"\tknows "), "qualifier")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: completion offers blocks at the top level", function()
	local bufnr = T.buffer({ "attacker[active]", "", "prin" }, "ctx.vp")
	T.eq(lang.completion_context(bufnr, 3, 0), "top")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: omnifunc finds the start of the word and filters by prefix", function()
	local bufnr = T.buffer({ "principal Alice[", "\tx = AEAD", "]" }, "ctx.vp")
	vim.api.nvim_win_set_cursor(0, { 2, #"\tx = AEAD" })
	T.eq(lang.omnifunc(1, ""), #"\tx = ", "word starts after the assignment")
	local items = lang.omnifunc(0, "AEAD")
	local words = vim.tbl_map(function(item)
		return item.word
	end, items)
	table.sort(words)
	T.eq(words, { "AEAD_DEC", "AEAD_ENC" })
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: omnifunc completes a lowercase prefix to the canonical name", function()
	local bufnr = T.buffer({ "principal Alice[", "\tx = pubk", "]" }, "ctx.vp")
	vim.api.nvim_win_set_cursor(0, { 2, #"\tx = pubk" })
	local items = lang.omnifunc(0, "pubk")
	T.eq(#items, 1)
	T.eq(items[1].word, "PUBKEY")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("lang: hover reports whether it handled the word", function()
	local bufnr = T.buffer({ "principal Alice[", "\tx = PUBKEY(a)", "]" }, "hover.vp")
	vim.api.nvim_win_set_cursor(0, { 2, 5 })
	T.eq(lang.hover(), true, "PUBKEY is documented")
	vim.api.nvim_win_set_cursor(0, { 2, 1 })
	T.eq(lang.hover(), false, "a constant name is not")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "markdown" then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)
