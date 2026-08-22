-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local format = require("verifpal.format")

local UGLY = {
	"attacker[passive]",
	"principal Alice[",
	"knows private fm_m",
	"fm_h    =    HASH(fm_m)",
	"]",
	"Alice -> Bob: fm_h",
	"principal Bob[",
	"_ = HASH(fm_h)",
	"]",
	"queries[",
	"confidentiality? fm_m",
	"]",
}

local function lines(bufnr)
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

T.test("format: reformats a buffer through the language server", function()
	local bufnr = T.buffer(UGLY)
	T.attached(bufnr)
	T.ok(format.format(bufnr))
	local text = table.concat(lines(bufnr), "\n")
	T.matches(text, "fm_h = HASH%(fm_m%)")
	T.matches(text, "\tfm_h")
end)

T.test("format: an already-canonical buffer is left alone", function()
	local bufnr = T.buffer(UGLY)
	T.attached(bufnr)
	format.format(bufnr)
	local before = lines(bufnr)
	vim.bo[bufnr].modified = false
	format.format(bufnr)
	T.eq(lines(bufnr), before)
	T.eq(vim.bo[bufnr].modified, false, "a no-op format does not dirty the buffer")
end)

T.test("format: the cursor stays put", function()
	local bufnr = T.buffer(UGLY)
	T.attached(bufnr)
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_cursor(win, { 6, 0 })
	format.format(bufnr)
	T.eq(vim.api.nvim_win_get_cursor(win)[1], 6)
end)

T.test("format: a buffer with no server attached reports rather than throwing", function()
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "attacker[passive]" })
	T.eq(format.format(bufnr, { silent = true }), false)
end)

T.test("format: a model that does not parse is left untouched", function()
	local bufnr = T.buffer({ "attacker[active]", "principal Alice[" })
	T.attached(bufnr)
	local before = lines(bufnr)
	format.format(bufnr)
	T.eq(lines(bufnr), before)
end)
