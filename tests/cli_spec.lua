-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local cli = require("verifpal.cli")

local NEW_STYLE = table.concat({
	"sanity error: `PUBKEY` takes 1 argument, but 2 were given",
	"  --> broken.vp:12:7",
	"   |",
	"12 |     ga = PUBKEY(a, c0)",
	"   |          ^^^^^^",
	"   |",
	"   = note: its signature is `PUBKEY(private_key)`",
	"   = help: drop the second argument",
}, "\n")

local LEGACY_STYLE = table.concat({
	"Error: broken.vp:12:2: sanity error: primitive has 2 inputs, expecting 1",
	"   ga = PUBKEY(a, c0)",
	"   ^^^^^^^^^^^^^^^^^^",
}, "\n")

T.test("cli: reads a position out of the current error format", function()
	local parsed = cli.parse_error(NEW_STYLE)
	T.eq(parsed.lnum, 11, "0-based line")
	T.eq(parsed.col, 6, "0-based column")
	T.eq(parsed.end_col, 12, "column plus caret width")
	T.eq(parsed.kind, "sanity error")
	T.matches(parsed.headline, "takes 1 argument")
end)

T.test("cli: carries note and help footnotes into the message", function()
	local parsed = cli.parse_error(NEW_STYLE)
	T.eq(#parsed.notes, 2)
	T.matches(parsed.message, "note: its signature")
	T.matches(parsed.message, "help: drop the second argument")
end)

T.test("cli: reads a position out of the 1.0.4 error format", function()
	local parsed = cli.parse_error(LEGACY_STYLE)
	T.eq(parsed.lnum, 11)
	T.eq(parsed.col, 1)
	T.eq(parsed.kind, "sanity error")
	T.matches(parsed.headline, "^sanity error: primitive has 2 inputs")
	T.ok(not parsed.headline:match("^Error:"), "the `Error:` prefix is stripped")
end)

T.test("cli: an error with no position still yields a message", function()
	local parsed = cli.parse_error("parse error: no `queries` block defined")
	T.eq(parsed.lnum, 0)
	T.eq(parsed.col, 0)
	T.matches(parsed.headline, "no `queries` block")
end)

T.test("cli: empty input is not an error", function()
	T.eq(cli.parse_error(""), nil)
	T.eq(cli.parse_error(nil), nil)
end)

T.test("cli: a missing binary is reported, not thrown", function()
	local config = require("verifpal.config")
	local saved = vim.deepcopy(config.options)
	config.apply({ path = "definitely-not-a-real-binary-xyz" })
	cli.reset()
	local path, err = cli.binary()
	T.eq(path, nil)
	T.matches(err, "not found in %$PATH")
	local result, run_err = cli.run_sync({ "--version" })
	T.eq(result, nil)
	T.ok(run_err ~= nil, "run_sync reports the same reason")
	config.options = saved
	cli.reset()
end)

T.test("cli: probes what the installed binary supports", function()
	local binary = T.binary()
	if not binary then
		T.skip("no verifpal binary")
	end
	local config = require("verifpal.config")
	local saved = vim.deepcopy(config.options)
	config.apply({ path = binary })
	cli.reset()

	local features = cli.features()
	for _, key in ipairs({ "json", "sessions", "quiet", "color", "diagram", "stdin" }) do
		T.eq(type(features[key]), "boolean", key .. " is answered either way")
	end
	T.eq(features.stdin, true, "every verifpal since 1.0.0 has internal-json")
	T.matches(cli.version() or "", "^%d+%.%d+%.%d+$")

	config.options = saved
	cli.reset()
end)
