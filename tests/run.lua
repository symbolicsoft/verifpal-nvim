-- SPDX-FileCopyrightText: © 2019-2026 Nadim Kobeissi <nadim@symbolic.software>
-- SPDX-License-Identifier: GPL-3.0-only

--- Headless test runner. No dependencies: `make test`, or
---
---     nvim --headless -u tests/minimal.lua -l tests/run.lua
---
--- Tests that need the verifpal binary skip themselves when it is absent, so
--- the suite is still meaningful on a machine that has only the plugin.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local T = {
	tests = {},
	current = nil,
	passed = 0,
	failed = 0,
	skipped = 0,
	failures = {},
}

function T.test(name, fn)
	T.tests[#T.tests + 1] = { name = name, fn = fn }
end

function T.skip(reason)
	error({ verifpal_skip = reason or "skipped" }, 0)
end

local function fail(message)
	error({ verifpal_fail = message }, 0)
end

function T.ok(value, message)
	if not value then
		fail(message or ("expected a truthy value, got " .. vim.inspect(value)))
	end
end

function T.eq(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail(
			string.format(
				"%s\n  expected: %s\n  actual:   %s",
				message or "values differ",
				vim.inspect(expected),
				vim.inspect(actual)
			)
		)
	end
end

function T.matches(text, pattern, message)
	if type(text) ~= "string" or not text:match(pattern) then
		fail(
			string.format(
				"%s\n  pattern: %s\n  text:    %s",
				message or "no match",
				pattern,
				vim.inspect(text)
			)
		)
	end
end

function T.wait(condition, timeout)
	local ok = vim.wait(timeout or 60000, condition, 20)
	if not ok then
		fail("timed out waiting for a condition")
	end
end

--- The verifpal to test against. `$VERIFPAL_BIN` wins, which is how the
--- suite is pointed at an older release to exercise the fallback paths;
--- otherwise a repo build beside this checkout beats whatever is on $PATH, so
--- the suite exercises the current interface when one is there.
function T.binary()
	local override = vim.env.VERIFPAL_BIN
	if override and override ~= "" then
		if vim.fn.executable(override) ~= 1 then
			error("VERIFPAL_BIN is not executable: " .. override, 0)
		end
		return override
	end
	local candidates = {
		root .. "/../verifpal/target/release/verifpal",
		root .. "/../verifpal/target/debug/verifpal",
	}
	for _, candidate in ipairs(candidates) do
		if vim.fn.executable(candidate) == 1 then
			return vim.fn.fnamemodify(candidate, ":p")
		end
	end
	local found = vim.fn.exepath("verifpal")
	if found ~= "" then
		return found
	end
	return nil
end

--- A scratch buffer holding `lines`, named so verifpal will accept it.
function T.buffer(lines, name)
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. "/" .. (name or "spec.vp"))
	vim.bo[bufnr].filetype = "verifpal"
	vim.bo[bufnr].modified = false
	vim.api.nvim_set_current_buf(bufnr)
	return bufnr
end

function T.model(name)
	local path = root .. "/tests/models/" .. name
	return vim.fn.readfile(path)
end

_G.T = T

local specs = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
	local chunk, err = loadfile(spec)
	if not chunk then
		io.stderr:write("could not load " .. spec .. ": " .. tostring(err) .. "\n")
		os.exit(1)
	end
	chunk()
end

for _, test in ipairs(T.tests) do
	local ok, err = pcall(test.fn)
	if ok then
		T.passed = T.passed + 1
		io.stdout:write(".")
	elseif type(err) == "table" and err.verifpal_skip then
		T.skipped = T.skipped + 1
		io.stdout:write("s")
	else
		T.failed = T.failed + 1
		local message = type(err) == "table" and err.verifpal_fail or tostring(err)
		T.failures[#T.failures + 1] = { name = test.name, message = message }
		io.stdout:write("F")
	end
end

io.stdout:write("\n\n")
for _, failure in ipairs(T.failures) do
	io.stdout:write("FAIL  " .. failure.name .. "\n")
	for _, line in ipairs(vim.split(failure.message, "\n", { plain = true })) do
		io.stdout:write("      " .. line .. "\n")
	end
	io.stdout:write("\n")
end
io.stdout:write(
	string.format(
		"%d passed, %d failed, %d skipped, %d total\n",
		T.passed,
		T.failed,
		T.skipped,
		#T.tests
	)
)

os.exit(T.failed == 0 and 0 or 1)
