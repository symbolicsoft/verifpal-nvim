-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local docs = require("verifpal.docs")

T.test("docs: all 25 primitives are documented", function()
	T.eq(vim.tbl_count(docs.primitives), 25)
end)

T.test("docs: every entry has a signature and a body", function()
	for _, group in ipairs({ docs.primitives, docs.queries, docs.assumptions, docs.keywords }) do
		for name, entry in pairs(group) do
			T.ok(entry.sig and entry.sig ~= "", name .. " has a signature")
			T.ok(entry.doc and #entry.doc > 20, name .. " has a body")
		end
	end
end)

T.test("docs: lookup is case-insensitive, as the language is", function()
	local upper = docs.lookup("AEAD_ENC")
	local lower = docs.lookup("aead_enc")
	T.ok(upper ~= nil and upper == lower, "`aead_enc` and `AEAD_ENC` are one call")
end)

T.test("docs: the five query kinds and `precondition` are covered", function()
	for _, kind in ipairs({
		"confidentiality",
		"authentication",
		"freshness",
		"unlinkability",
		"equivalence",
		"precondition",
	}) do
		local entry, category = docs.lookup(kind)
		T.ok(entry ~= nil, kind .. " is documented")
		T.eq(category, "query")
	end
end)

T.test("docs: weakening assumptions name the primitives that accept them", function()
	T.matches(docs.assumptions.weak.doc, "PUBKEY")
	T.matches(docs.assumptions.forgeable.doc, "SIGN")
	-- `malleable` is implemented on ENC. It was once documented as accepted by
	-- nothing, which made the plugin describe a check verifpal performs as one
	-- it refuses.
	T.matches(docs.assumptions.malleable.doc, "ENC")
	T.ok(
		not docs.assumptions.malleable.doc:match("No primitive"),
		"`malleable` is not described as unimplemented"
	)
end)

T.test("docs: the assumption a primitive declares matches the engine", function()
	local expected = {
		HASH = { "weak" },
		PW_HASH = { "weak" },
		PUBKEY = { "weak" },
		PKE_ENC = { "weak" },
		KEM_ENCAP = { "weak" },
		ENC = { "weak", "malleable" },
		AEAD_ENC = { "weak", "forgeable" },
		MAC = { "forgeable" },
		SIGN = { "forgeable" },
		RINGSIGN = { "forgeable" },
	}
	for name, want in pairs(expected) do
		T.eq(docs.primitives[name].assumptions, want, name .. " assumptions")
	end
	for name, entry in pairs(docs.primitives) do
		if not expected[name] then
			T.eq(entry.assumptions, nil, name .. " declares no assumption")
		end
	end
end)

T.test("docs: only the six checkable primitives are marked checkable", function()
	local checkable = {
		ASSERT = true,
		SPLIT = true,
		AEAD_DEC = true,
		SIGNVERIF = true,
		RINGSIGNVERIF = true,
		KEM_DECAP = true,
	}
	for name, entry in pairs(docs.primitives) do
		T.eq(entry.checked ~= nil, checkable[name] == true, name .. " checkability")
	end
end)

T.test("docs: render puts the facts line between signature and body", function()
	local entry, category = docs.lookup("KEM_ENCAP")
	local lines = docs.render("KEM_ENCAP", entry, category)
	T.eq(lines[1], "**KEM_ENCAP**")
	T.matches(lines[3], "KEM_ENCAP%(encapsulation_key, randomness%)`$")
	T.matches(lines[5], "2 arguments · 2 outputs · accepts `%[weak%]`")
end)

T.test("docs: completions cover every documented word", function()
	local items = docs.completions()
	local seen = {}
	for _, item in ipairs(items) do
		seen[item.word] = item.kind
	end
	T.eq(seen.AEAD_ENC, "primitive")
	T.eq(seen.confidentiality, "query")
	T.eq(seen.forgeable, "assumption")
	T.eq(seen.principal, "keyword")
	T.eq(seen.nil_, nil, "the internal key for `nil` is not offered as a word")
end)

T.test("docs: primitive names match the engine's own list", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local config = require("verifpal.config")
	local cli = require("verifpal.cli")
	local saved = vim.deepcopy(config.options)
	config.apply({ path = binary })
	cli.reset()

	-- A primitive the plugin documents but the engine does not know is a stale
	-- doc; the model below asks verifpal about each one directly.
	local unknown = {}
	for name, entry in pairs(docs.primitives) do
		local arity = tonumber(entry.arity:match("^(%d+)")) or 1
		local args = {}
		for i = 1, arity do
			args[i] = "a" .. i
		end
		local model = table.concat({
			"attacker[passive]",
			"principal Alice[",
			"\tknows public " .. table.concat(args, ", "),
			"\tout = " .. name .. "(" .. table.concat(args, ", ") .. ")",
			"]",
			"queries[",
			"\tconfidentiality? a1",
			"]",
			"",
		}, "\n")
		local result = cli.run_sync({ "internal-json", "knowledgeMap" }, { stdin = model })
		if result and result.stderr:match("unknown primitive") then
			unknown[#unknown + 1] = name
		end
	end
	T.eq(unknown, {}, "every documented primitive is known to verifpal")

	config.options = saved
	cli.reset()
end)
