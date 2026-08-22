-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

local config = require("verifpal.config")

local function with_config(opts, fn)
	local saved = vim.deepcopy(config.options)
	local problems = config.apply(opts)
	local ok, err = pcall(fn, problems)
	config.options = saved
	if not ok then
		error(err, 0)
	end
end

T.test("config: defaults are complete without a setup call", function()
	T.eq(type(config.get("path")), "string")
	T.eq(type(config.get("timeout")), "number")
	T.eq(config.get("diagnostics.enabled"), true)
end)

T.test("config: a user table merges over the defaults", function()
	with_config({ path = "/opt/verifpal", diagnostics = { pass = false } }, function(problems)
		T.eq(problems, {}, "no problems")
		T.eq(config.get("path"), "/opt/verifpal")
		T.eq(config.get("diagnostics.pass"), false)
		T.eq(config.get("diagnostics.enabled"), true, "untouched keys keep their default")
	end)
end)

T.test("config: a misspelled option is reported, not ignored", function()
	with_config({ sesions = 3 }, function(problems)
		T.eq(#problems, 1)
		T.matches(problems[1], "unknown option `sesions`")
	end)
end)

T.test("config: a nested misspelled option names its full path", function()
	with_config({ diagnostics = { atack = 1 } }, function(problems)
		T.eq(#problems, 1)
		T.matches(problems[1], "diagnostics%.atack")
	end)
end)

T.test("config: `sessions` is nil by default and still not a typo", function()
	with_config({ sessions = 4 }, function(problems)
		T.eq(problems, {})
		T.eq(config.get("sessions"), 4)
	end)
end)

T.test("config: an out-of-range session count is rejected", function()
	with_config({ sessions = 99 }, function(problems)
		T.eq(#problems, 1)
		T.matches(problems[1], "between 1 and 16")
	end)
end)

T.test("config: hover_key accepts a string or false", function()
	with_config({ hover_key = false }, function(problems)
		T.eq(problems, {})
	end)
	with_config({ hover_key = 3 }, function(problems)
		T.eq(#problems, 1)
	end)
end)

T.test("config: a bad option still lets the rest through", function()
	with_config({ timeout = -1, path = "/opt/verifpal" }, function(problems)
		T.eq(#problems, 1)
		T.eq(config.get("path"), "/opt/verifpal")
	end)
end)
