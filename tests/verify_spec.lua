-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local cli = require("verifpal.cli")
local config = require("verifpal.config")
local verify = require("verifpal.verify")

T.test("verify: parses a result code into per-query verdicts", function()
	T.eq(verify.parse_result_code("c1a0"), {
		{ kind = "confidentiality", resolved = true },
		{ kind = "authentication", resolved = false },
	})
	T.eq(verify.parse_result_code(""), {}, "a model with no queries has an empty code")
	T.eq(verify.parse_result_code("c0a1f0u1e0"), {
		{ kind = "confidentiality", resolved = false },
		{ kind = "authentication", resolved = true },
		{ kind = "freshness", resolved = false },
		{ kind = "unlinkability", resolved = true },
		{ kind = "equivalence", resolved = false },
	})
end)

T.test("verify: refuses to read a malformed result code", function()
	T.eq(verify.parse_result_code("c"), nil, "odd length")
	T.eq(verify.parse_result_code("z0"), nil, "unknown query kind")
	T.eq(verify.parse_result_code("c2"), nil, "a verdict is 0 or 1")
	T.eq(verify.parse_result_code("Thank you"), nil, "prose is not a code")
	T.eq(verify.parse_result_code(nil), nil)
end)

--- Run one model to completion against the real binary.
local function analyze(name, opts)
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	config.apply(vim.tbl_extend("force", { path = binary, notify = false }, opts or {}))
	cli.reset()

	local bufnr = T.buffer(T.model(name), name)
	local report
	verify.verify(bufnr, {
		silent = true,
		on_done = function(r)
			report = r
		end,
	})
	T.wait(function()
		return report ~= nil
	end, 120000)

	local diagnostics = vim.diagnostic.get(bufnr, { namespace = verify.namespace() })
	config.options = saved
	cli.reset()
	return report, bufnr, diagnostics
end

T.test("verify: a clean model reports every query holding", function()
	local report, bufnr = analyze("plain.vp")
	T.eq(report.error, nil)
	T.eq(report.code, "c0f0")
	T.eq(report.attacks, 0)
	T.eq(#report.queries, 2)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: each verdict lands on the query that produced it", function()
	local report, bufnr, diagnostics = analyze("tricky.vp")
	T.eq(report.error, nil)
	T.eq(report.aligned, true, "results matched query lines")
	T.eq(#diagnostics, #report.queries, "one diagnostic per query")

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	table.sort(diagnostics, function(a, b)
		return a.lnum < b.lnum
	end)
	local queries = require("verifpal.scan").queries(lines)
	for i, diagnostic in ipairs(diagnostics) do
		T.eq(diagnostic.lnum, queries[i].lnum, "diagnostic " .. i .. " is on its query")
		T.matches(lines[diagnostic.lnum + 1], queries[i].kind)
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: a contradicted query is an error and a held one is not", function()
	local report, bufnr, diagnostics = analyze("tricky.vp")
	local by_line = {}
	for _, diagnostic in ipairs(diagnostics) do
		by_line[diagnostic.lnum] = diagnostic
	end
	local queries = require("verifpal.scan").queries(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
	for i, result in ipairs(report.queries) do
		local diagnostic = by_line[queries[i].lnum]
		T.ok(diagnostic ~= nil, "query " .. i .. " has a diagnostic")
		if result.resolved then
			T.eq(diagnostic.severity, vim.diagnostic.severity.ERROR)
			T.matches(diagnostic.message, "^attack found")
		else
			T.eq(diagnostic.severity, vim.diagnostic.severity.INFO)
			T.matches(diagnostic.message, "^no attack found")
		end
	end
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: a model error becomes a diagnostic on its own line", function()
	local report, bufnr, diagnostics = analyze("broken.vp")
	T.ok(report.error ~= nil, "the model does not verify")
	T.eq(#diagnostics, 1)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	T.matches(lines[diagnostics[1].lnum + 1], "PUBKEY%(a, c0%)", "diagnostic is on the bad call")
	T.eq(diagnostics[1].severity, vim.diagnostic.severity.ERROR)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: `diagnostics.pass = false` leaves held queries unmarked", function()
	local report, bufnr, diagnostics = analyze("tricky.vp", { diagnostics = { pass = false } })
	local attacks = 0
	for _, result in ipairs(report.queries) do
		if result.resolved then
			attacks = attacks + 1
		end
	end
	T.eq(#diagnostics, attacks, "only contradicted queries are marked")
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: an unsaved buffer is analyzed as it stands", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	config.apply({ path = binary, notify = false })
	cli.reset()

	-- No file name at all, so there is nothing on disk to fall back to.
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, T.model("plain.vp"))
	local report
	verify.verify(bufnr, {
		silent = true,
		on_done = function(r)
			report = r
		end,
	})
	T.wait(function()
		return report ~= nil
	end, 120000)
	T.eq(report.error, nil, "an unnamed buffer still verifies")
	T.eq(report.code, "c0f0")

	vim.api.nvim_buf_delete(bufnr, { force = true })
	config.options = saved
	cli.reset()
end)

T.test("verify: verifying never writes the buffer to disk", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local saved = vim.deepcopy(config.options)
	config.apply({ path = binary, notify = false })
	cli.reset()

	local path = vim.fn.tempname() .. ".vp"
	vim.fn.writefile(T.model("plain.vp"), path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "// an edit the user has not saved" })
	T.eq(vim.bo[bufnr].modified, true)

	local report
	verify.verify(bufnr, {
		silent = true,
		on_done = function(r)
			report = r
		end,
	})
	T.wait(function()
		return report ~= nil
	end, 120000)

	T.eq(vim.bo[bufnr].modified, true, "the buffer is still unsaved")
	T.eq(vim.fn.readfile(path), T.model("plain.vp"), "the file on disk is untouched")
	T.eq(report.error, nil, "and the edited buffer is what was analyzed")

	vim.api.nvim_buf_delete(bufnr, { force = true })
	vim.fn.delete(path)
	config.options = saved
	cli.reset()
end)

T.test("verify: status reports the verdict once an analysis has finished", function()
	local report, bufnr = analyze("tricky.vp")
	T.ok(report ~= nil)
	T.matches(verify.status(bufnr), "attack")
	verify.clear(bufnr)
	T.eq(verify.status(bufnr), "")
	T.eq(#vim.diagnostic.get(bufnr, { namespace = verify.namespace() }), 0)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: a model that asks nothing is not a failed run", function()
	local report, bufnr = analyze("noqueries.vp")
	-- The result code for a model with no queries is the empty string, which
	-- is only distinguishable from a failed run by taking the *last* line of
	-- output rather than the last non-empty one.
	T.eq(report.error, nil)
	T.eq(report.code, "")
	T.eq(#report.queries, 0)
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: 0 addresses the current buffer, not a buffer of its own", function()
	local report, bufnr = analyze("plain.vp")
	T.ok(report ~= nil)
	vim.api.nvim_set_current_buf(bufnr)
	-- Neovim reads 0 as "the current buffer". Keying state on the literal 0
	-- filed a buffer's results where nothing else looked for them, so
	-- :VerifpalResults re-ran the analysis instead of showing it.
	T.ok(verify.report(0) ~= nil, "the report is reachable through 0")
	T.eq(verify.report(0), verify.report(bufnr))
	T.eq(verify.status(0), verify.status(bufnr))
	vim.api.nvim_buf_delete(bufnr, { force = true })
end)

T.test("verify: a bad binary path is reported without throwing", function()
	local saved = vim.deepcopy(config.options)
	config.apply({ path = "definitely-not-a-real-binary-xyz", notify = false })
	cli.reset()
	local bufnr = T.buffer(T.model("plain.vp"), "plain.vp")
	verify.verify(bufnr, { silent = true })
	T.eq(verify.running(bufnr), false, "nothing was started")
	vim.api.nvim_buf_delete(bufnr, { force = true })
	config.options = saved
	cli.reset()
end)
