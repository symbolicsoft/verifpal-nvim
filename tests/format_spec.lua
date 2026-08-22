-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local cli = require("verifpal.cli")
local config = require("verifpal.config")
local format = require("verifpal.format")

T.test("format: an unchanged buffer produces no edit at all", function()
	T.eq(format.diff_range({ "a", "b" }, { "a", "b" }), nil)
end)

T.test("format: only the changed lines are replaced", function()
	local first, last, replacement =
		format.diff_range({ "a", "b", "c", "d" }, { "a", "B", "c", "d" })
	T.eq(first, 2)
	T.eq(last, 2)
	T.eq(replacement, { "B" })
end)

T.test("format: an insertion is a zero-width replacement", function()
	local first, last, replacement = format.diff_range({ "a", "d" }, { "a", "b", "c", "d" })
	T.eq(first, 2)
	T.eq(last, 1, "nothing is removed")
	T.eq(replacement, { "b", "c" })
end)

T.test("format: a deletion replaces with nothing", function()
	local first, last, replacement = format.diff_range({ "a", "b", "c" }, { "a", "c" })
	T.eq(first, 2)
	T.eq(last, 2)
	T.eq(replacement, {})
end)

T.test("format: a change at the end of the buffer is bounded correctly", function()
	local first, last, replacement = format.diff_range({ "a", "b" }, { "a", "b", "c" })
	T.eq(first, 3)
	T.eq(last, 2)
	T.eq(replacement, { "c" })
end)

local function with_binary(fn)
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	config.apply({ path = binary, notify = false })
	cli.reset()
	local ok, err = pcall(fn)
	config.options = saved
	cli.reset()
	if not ok then
		error(err, 0)
	end
end

T.test("format: reformats a buffer and keeps the cursor put", function()
	with_binary(function()
		local bufnr = T.buffer({
			"attacker[active]",
			"principal Alice[",
			"knows public c0",
			"  generates a",
			"\tga=PUBKEY( a )",
			"]",
			"queries[",
			"confidentiality? a",
			"]",
		}, "messy.vp")
		vim.api.nvim_win_set_cursor(0, { 5, 3 })
		local ok, changed = format.format(bufnr, { silent = true })
		T.eq(ok, true)
		T.eq(changed, true)
		T.eq(vim.api.nvim_win_get_cursor(0), { 5, 3 }, "the cursor did not move")
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		T.eq(lines[6], "\tga = PUBKEY(a)")
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)

T.test("format: formatting an already-canonical buffer is a no-op", function()
	with_binary(function()
		local bufnr = T.buffer(T.model("plain.vp"), "plain.vp")
		local ok, changed = format.format(bufnr, { silent = true })
		T.eq(ok, true)
		T.eq(changed, false, "nothing to do")
		T.eq(vim.bo[bufnr].modified, false, "so the buffer is not marked modified")
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)

T.test("format: comments survive a round trip", function()
	with_binary(function()
		local bufnr = T.buffer(T.model("tricky.vp"), "tricky.vp")
		format.format(bufnr, { silent = true })
		local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		T.matches(text, "SPDX%-License%-Identifier", "the header comment is kept")
		T.matches(text, "a block comment holding a bracket", "block comments are kept")
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)

T.test("format: a model that does not parse leaves the buffer alone", function()
	with_binary(function()
		local original = { "attacker[active]", "principal Alice[", "\tga = PUBKEY(" }
		local bufnr = T.buffer(vim.deepcopy(original), "unparseable.vp")
		local ok = format.format(bufnr, { silent = true })
		T.eq(ok, false)
		T.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), original)
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)

T.test("format: is_formatted agrees with format", function()
	with_binary(function()
		local features = cli.features()
		if not features.stdin then
			T.skip("this verifpal cannot format from stdin")
		end
		local bufnr = T.buffer(T.model("plain.vp"), "plain.vp")
		T.eq(format.is_formatted(bufnr), true)
		vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "   " })
		T.eq(format.is_formatted(bufnr), false)
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)
