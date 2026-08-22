-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local scan = require("verifpal.scan")

local function kinds(queries)
	return vim.tbl_map(function(q)
		return q.kind
	end, queries)
end

T.test("scan: finds every query in model order", function()
	local lines = T.model("tricky.vp")
	local queries = scan.queries(lines)
	T.eq(
		kinds(queries),
		{ "confidentiality", "authentication", "freshness", "equivalence" },
		"query kinds in model order"
	)
end)

T.test("scan: a query after a multi-line option block keeps its own line", function()
	local lines = T.model("tricky.vp")
	local queries = scan.queries(lines)
	for _, query in ipairs(queries) do
		local text = lines[query.lnum + 1]
		T.matches(text, "^%s*" .. query.kind .. "%s*%?", "query anchored on its own line")
	end
end)

T.test("scan: a bracket inside a comment does not close a block", function()
	local queries, block = scan.queries(T.model("tricky.vp"))
	T.eq(#queries, 4, "the block comment holding `]` did not truncate the model")
	T.ok(block ~= nil, "queries block found")
	T.ok(block.end_lnum > block.start_lnum, "queries block spans lines")
end)

T.test("scan: `precondition` inside an option block is not a query", function()
	local queries = scan.queries({
		"queries[",
		"\tauthentication? Alice -> Bob: e[",
		"\t\tprecondition[Bob -> Alice: ack]",
		"\t]",
		"]",
	})
	T.eq(#queries, 1, "one query")
	T.eq(queries[1].kind, "authentication")
	T.eq(queries[1].lnum, 1)
end)

T.test("scan: query kinds are matched case-insensitively", function()
	local queries = scan.queries({ "queries[", "\tCONFIDENTIALITY? m", "]" })
	T.eq(#queries, 1)
	T.eq(queries[1].kind, "confidentiality")
end)

T.test("scan: a query word without `?` is not a query", function()
	local queries = scan.queries({ "queries[", "\tconfidentiality m", "]" })
	T.eq(#queries, 0, "the `?` is what makes a query")
end)

T.test("scan: guards and capability parameters do not change line depth", function()
	local depths = scan.depths({
		"principal Alice[",
		"\te = AEAD_ENC[weak, forgeable from phase 1](k, m, c0)",
		"]",
		"Alice -> Bob: [ga], e",
	})
	T.eq(depths[2].start, 1, "inside the principal block")
	T.eq(depths[2].finish, 1, "capability brackets open and close on one line")
	T.eq(depths[3].closes, true, "the block's `]` closes it")
	T.eq(depths[4].start, 0, "a guarded message sits at the top level")
	T.eq(depths[4].finish, 0, "a guard opens and closes on one line")
end)

T.test("scan: an unterminated block comment swallows the rest of the file", function()
	local queries = scan.queries({ "/* queries[", "confidentiality? m", "]" })
	T.eq(#queries, 0, "nothing is code after an unterminated block comment")
end)

T.test("scan: blank_comments preserves every column", function()
	local blanked = scan.blank_comments({
		"knows public c0 // a trailing comment",
		"x = HASH(a) /* inline */ // and another",
	})
	T.eq(#blanked[1], #"knows public c0 // a trailing comment")
	T.eq(#blanked[2], #"x = HASH(a) /* inline */ // and another")
	T.eq(blanked[1], "knows public c0" .. string.rep(" ", 22))
	T.matches(blanked[2], "^x = HASH%(a%) +$")
end)

T.test("scan: an unclosed bracket never drives depth below zero", function()
	local depths = scan.depths({ "]", "]", "principal Alice[" })
	T.eq(depths[1].start, 0)
	T.eq(depths[2].start, 0)
	T.eq(depths[3].finish, 1)
end)
