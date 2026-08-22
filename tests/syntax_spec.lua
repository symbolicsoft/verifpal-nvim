-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Highlighting is asserted by asking Vim which group it resolved a column to,
--- so these hold against the real syntax engine rather than against a reading
--- of the patterns.

local function highlight(lines)
	local bufnr = T.buffer(lines, "syntax.vp")
	-- Re-trigger FileType so this buffer's syntax is parsed from its own
	-- first line: without it the state left by the previous test's buffer can
	-- still be in force.
	vim.bo[bufnr].filetype = ""
	vim.bo[bufnr].filetype = "verifpal"
	vim.cmd("syntax sync fromstart")
	return bufnr
end

--- The syntax group at a 1-based line and column.
local function group_at(lnum, col)
	local id = vim.fn.synID(lnum, col, 1)
	if id == 0 then
		return nil
	end
	return vim.fn.synIDattr(id, "name")
end

--- The group covering the first occurrence of `needle` on `lnum`.
local function group_of(lnum, needle)
	local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
	local at = line:find(needle, 1, true)
	T.ok(at ~= nil, "found " .. needle .. " on line " .. lnum)
	return group_at(lnum, at)
end

T.test("syntax: the Unicode arrow is a message transfer", function()
	local bufnr = highlight({ "Alice → Bob: ga", "Alice -> Bob: gb" })
	-- `→` in a Vim pattern is "an uppercase letter, then 2192". Writing
	-- the arrow that way matched `A2192` and never the arrow itself.
	T.eq(group_of(1, "→"), "verifpalTransfer")
	T.eq(group_of(2, "->"), "verifpalTransfer")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: primitives are recognised in either case", function()
	local bufnr = highlight({
		"principal Alice[",
		"\tx = AEAD_ENC(k, m, c0)",
		"\ty = aead_enc(k, m, c0)",
		"]",
	})
	T.eq(group_of(2, "AEAD_ENC"), "verifpalPrimitive")
	T.eq(group_of(3, "aead_enc"), "verifpalPrimitive", "verifpal resolves names case-insensitively")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: weakening assumptions highlight inside a parameter list", function()
	local bufnr = highlight({
		"principal Alice[",
		"\tga = PUBKEY[weak from phase 1](a)",
		"\te = AEAD_ENC[weak, forgeable](k, m, c0)",
		"\tg = ENC[malleable](k, m)",
		"]",
	})
	T.eq(group_of(2, "weak"), "verifpalCapability")
	T.eq(group_of(2, "from"), "verifpalCapability")
	T.eq(group_of(2, "phase"), "verifpalCapability", "not the top-level `phase` block keyword")
	T.eq(group_of(3, "forgeable"), "verifpalCapability")
	T.eq(group_of(4, "malleable"), "verifpalCapability")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: a constant may still be called `weak` or `from`", function()
	local bufnr = highlight({
		"principal Alice[",
		"\tknows public weak, from",
		"\tx = HASH(weak, from)",
		"]",
	})
	T.eq(group_of(2, "weak"), nil, "a constant, not a capability")
	T.eq(group_of(3, "from"), nil)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: a guarded value is not a parameter list", function()
	local bufnr = highlight({ "Alice -> Bob: [weak], e" })
	T.eq(group_of(1, "weak"), nil, "a guard holds a constant, not an assumption")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: a checked primitive's `?` is its own group", function()
	local bufnr = highlight({ "principal Bob[", "\tm = AEAD_DEC(k, e, c0)?", "]" })
	T.eq(group_of(2, "?"), "verifpalCheck")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: comments are comments all the way down", function()
	local bufnr = highlight({
		"// principal Alice[ AEAD_ENC",
		"/* queries[",
		"   confidentiality? m",
		"*/",
		"knows public c0",
	})
	T.eq(group_of(1, "principal"), "verifpalComment")
	T.eq(group_of(1, "AEAD_ENC"), "verifpalComment")
	T.eq(group_of(3, "confidentiality"), "verifpalComment")
	T.eq(group_of(5, "knows"), "verifpalDeclaration", "and code after one is code again")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: the anonymous constant and nil are special values", function()
	local bufnr = highlight({ "principal Alice[", "\t_ = HASH(nil)", "]" })
	T.eq(group_of(2, "_"), "verifpalSpecial")
	T.eq(group_of(2, "nil"), "verifpalSpecial")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("syntax: every primitive the plugin documents is highlighted", function()
	local docs = require("verifpal.docs")
	local names = vim.tbl_keys(docs.primitives)
	table.sort(names)
	local lines = { "principal Alice[" }
	for _, name in ipairs(names) do
		lines[#lines + 1] = "\tout = " .. name .. "(a)"
	end
	lines[#lines + 1] = "]"
	local bufnr = highlight(lines)
	for i, name in ipairs(names) do
		T.eq(group_of(i + 1, name), "verifpalPrimitive", name .. " is highlighted")
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)
