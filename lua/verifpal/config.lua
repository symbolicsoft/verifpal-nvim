-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Plugin configuration.
---
--- Every option has a default that works with no setup call at all, so
--- `require("verifpal")` alone is a complete installation. `setup()` merges a
--- user table over these and validates it: a typo in an option name is
--- reported rather than silently ignored, because an option that quietly does
--- nothing reads as a setting that was applied.

local M = {}

M.defaults = {
	--- Path to the verifpal binary, or a bare name looked up in $PATH.
	path = "verifpal",

	--- Sessions per principal. nil defers to the binary's own default (2).
	sessions = nil,

	--- Verify the buffer after every write.
	verify_on_save = false,

	--- Reformat the buffer before every write.
	format_on_save = false,

	--- vim.notify on summaries, warnings and errors.
	notify = true,

	panel = {
		--- Split command used to open the results panel.
		split = "botright",
		height = 20,
		--- Move the cursor into the panel when it opens.
		focus = true,
	},
}

--- The active configuration. Replaced wholesale by setup().
M.options = vim.deepcopy(M.defaults)

--- Options whose default is nil, and which `validate` must therefore not
--- mistake for a typo.
local nilable = { sessions = true }

local function type_of(value)
	if value == nil then
		return "nil"
	end
	return type(value)
end

--- Validate `user` against `defaults` recursively, collecting every problem
--- rather than stopping at the first: a user fixing their config wants the
--- whole list.
local function validate(user, defaults, path, problems)
	for key, value in pairs(user) do
		local full = path == "" and key or (path .. "." .. key)
		local expected = defaults[key]
		if expected == nil and not (path == "" and nilable[key]) then
			problems[#problems + 1] = string.format("unknown option `%s`", full)
		elseif type(expected) == "table" then
			if type(value) ~= "table" then
				problems[#problems + 1] =
					string.format("`%s` expects a table, got %s", full, type_of(value))
			else
				validate(value, expected, full, problems)
			end
		end
	end
	return problems
end

local function check_shapes(opts, problems)
	if opts.path ~= nil and type(opts.path) ~= "string" then
		problems[#problems + 1] = "`path` expects a string"
	end
	if opts.sessions ~= nil then
		local n = opts.sessions
		if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > 16 then
			problems[#problems + 1] = "`sessions` expects an integer between 1 and 16"
		end
	end
	return problems
end

--- Merge `opts` over the defaults. Returns the problems found, if any; the
--- merge happens regardless, so one bad option never costs the rest.
function M.apply(opts)
	opts = opts or {}
	local problems = {}
	if type(opts) ~= "table" then
		return { "setup() expects a table" }
	end
	validate(opts, M.defaults, "", problems)
	check_shapes(opts, problems)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
	return problems
end

--- Read a dotted option path, e.g. get("diagnostics.attack").
function M.get(path)
	local node = M.options
	for part in tostring(path):gmatch("[^.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

return M
