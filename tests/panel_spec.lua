-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local panel = require("verifpal.panel")

local REPORT = {
	code = "c1a0",
	sessions = 2,
	elapsed_ms = 7,
	attacks = 1,
	assumptions = {
		{ term = "PUBKEY[weak](a)", capability = "weak", from_phase = 0 },
		{ term = "SIGN[forgeable](sk, m)", capability = "forgeable", from_phase = 2 },
	},
	queries = {
		{
			query = "confidentiality? m",
			kind = "confidentiality",
			resolved = true,
			conclusion = "m (m) is obtained by Attacker.",
			trace = { "1. Attacker observes e on the wire.", "2. Attacker opens e with k." },
			preconditions = { "Bob sends ack to Alice despite the query failing." },
		},
		{
			query = "authentication? Alice -> Bob: e",
			kind = "authentication",
			resolved = false,
			conclusion = "",
			trace = {},
			preconditions = {},
		},
	},
}

local function text(lines)
	return table.concat(lines, "\n")
end

T.test("panel: a report shows the verdict, the trace and the counts", function()
	local lines = panel.render_report(REPORT, "example.vp")
	local body = text(lines)
	T.matches(body, "Verifpal — example.vp")
	T.matches(body, "c1a0")
	T.matches(body, "2 sessions")
	T.matches(body, "1 of 2 contradicted")
	T.matches(body, "FAIL  confidentiality%? m")
	T.matches(body, "PASS  authentication%? Alice %-> Bob: e")
	T.matches(body, "1%. Attacker observes e on the wire%.")
	T.matches(body, "Bob sends ack to Alice despite the query failing%.")
end)

T.test("panel: declared assumptions are shown as conditions on every verdict", function()
	local body = text(panel.render_report(REPORT, "example.vp"))
	T.matches(body, "Declared weakening assumptions")
	T.matches(body, "conditional on them")
	T.matches(body, "PUBKEY%[weak%]%(a%)")
	T.matches(body, "SIGN%[forgeable%]%(sk, m%)  %(from phase 2%)")
end)

T.test("panel: a model error is shown instead of a verdict", function()
	local body = text(panel.render_report({
		error = "parse error: no `queries` block defined\n --> m.vp:5:2",
		queries = {},
	}, "m.vp"))
	T.matches(body, "no `queries` block defined")
	T.ok(not body:match("FAIL"), "no verdicts are invented")
end)

T.test("panel: a model with no queries says so", function()
	local body = text(panel.render_report({ code = "", attacks = 0, queries = {} }, "empty.vp"))
	T.matches(body, "declares no queries")
end)

T.test("panel: an older binary's report says what is missing", function()
	local body = text(panel.render_report({
		code = "c1",
		attacks = 1,
		degraded = true,
		queries = { { kind = "confidentiality", resolved = true, trace = {} } },
	}, "old.vp"))
	T.matches(body, "predates `verify %-%-format json`")
end)

T.test("panel: a jump target is recorded for every query", function()
	local _, _, jumps = panel.render_report(REPORT, "example.vp")
	local indices = vim.tbl_values(jumps)
	table.sort(indices)
	T.eq(indices, { 1, 2 }, "both queries can be jumped to")
end)

T.test("panel: highlights stay inside the lines they mark", function()
	local lines, highlights = panel.render_report(REPORT, "example.vp")
	for _, hl in ipairs(highlights) do
		local line = lines[hl.lnum + 1]
		T.ok(line ~= nil, "highlight " .. hl.lnum .. " has a line")
		T.ok(hl.col >= 0 and hl.col <= #line, "start column is inside the line")
		T.ok(hl.end_col <= #line, "end column is inside the line")
	end
end)

T.test("panel: a diagram reads as principals and the messages between them", function()
	local lines = panel.render_diagram({
		"sequenceDiagram",
		"Note over Alice: knows public c0",
		"Note over Alice: ga = PUBKEY(a)",
		"Alice->Bob:ga",
		"Note over Bob: gab = DH_KEX(ga, b)",
	})
	local body = text(lines)
	T.matches(body, "^Alice\n")
	T.matches(body, "    knows public c0")
	T.matches(body, "Alice ──▶ Bob :  ga")
	T.matches(body, "Bob\n    gab = DH_KEX")
	T.ok(not body:match("sequenceDiagram"), "the mermaid header is not part of the rendering")
end)

T.test("panel: a model with no messages still renders", function()
	local body = text(panel.render_diagram({}))
	T.matches(body, "no messages")
end)
